# Usage

## What this is for

This framework exists so trigger logic doesn't end up scattered across ad-hoc trigger files with inconsistent structure. Instead:

- Each object gets **one** trigger, which does nothing but call `TriggerHandlerManager.handle('ObjectApiName')`.
- Business logic lives in handler classes that extend `TriggerHandler` and override only the hooks they need.
- Which handlers run, for which object, for which events, and in what order is **configuration** (`Trigger_Handler__mdt` records) — not code. Enabling, disabling, or reordering a handler doesn't require a deploy.

## Adding a new handler

1. Create a class that extends `TriggerHandler` and implements only the hooks it needs:

   ```apex
   public class AccountDefaultsHandler extends TriggerHandler {
       protected override void beforeInsert(List<SObject> newList) {
           // your logic here
       }
   }
   ```

2. Create a `Trigger_Handler__mdt` record for it:
   - `Class_Name__c` — the exact API name of the class (e.g. `AccountDefaultsHandler`).
   - `Object__c` — the API name of the SObject it handles (e.g. `Account`).
   - `Is_Active__c` — must be `true` for it to run at all.
   - Check the event checkboxes it should respond to (`Before_Insert__c`, `After_Update__c`, etc.).
   - `Order__c` — controls execution order relative to other handlers on the same object/event.

3. Make sure a trigger exists for that object and calls `TriggerHandlerManager.handle('ObjectApiName')`. If one already exists, you don't need to touch it — your new handler picks up automatically through the metadata record.

4. Create a test class for it. Every handler ships with its own tests — don't rely on `TriggerHandlerManagerTest` to cover your handler's logic, it only tests the manager's dispatch behavior. See [Testing your handlers](#testing-your-handlers).

5. Run `TriggerHandlerManager.validateConfiguration()` (the shipped test `activeConfigurationInThisOrgIsValid` does it on every deploy). It reports a misspelled class, a class that doesn't compile or isn't a handler, a missing object, or a record with no event selected.

## Recommended pattern: keep the handler thin, do the work async

Inside a hook (`beforeInsert`, `afterUpdate`, etc.), only inspect the `List<SObject>`/`Map<Id,SObject>` you were given to decide **whether** something needs to happen — no SOQL, no DML in the handler itself. If it does, hand off the record Ids to a Queueable (or a Batchable for larger volumes) and do the actual querying/DML there.

Why: the handler runs synchronously inside the same transaction as every other handler on that object/event, sharing one set of governor limits. Keeping it to list/map checks only means it stays cheap no matter how many handlers stack up. The async job gets its own fresh limits to do the real work.

```apex
public class AccountRegionAssignmentHandler extends TriggerHandler {
    protected override void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        Set<Id> idsToProcess = new Set<Id>();
        for (SObject sObj : newList) {
            Account acc = (Account) sObj;
            Account oldAcc = (Account) oldMap.get(acc.Id);
            if (acc.BillingCountry != oldAcc.BillingCountry) {
                idsToProcess.add(acc.Id);
            }
        }
        if (!idsToProcess.isEmpty()) {
            System.enqueueJob(new AccountRegionAssignmentQueueable(idsToProcess));
        }
    }
}
```

`AccountRegionAssignmentQueueable` is where the SOQL and DML actually live — it takes the Ids, queries what it needs, and does the work outside the trigger's transaction.

## Testing your handlers

You can test a handler two ways.

**Through real DML**, the usual way: insert or update records in your test and assert the result. This needs the object's trigger and the handler's `Trigger_Handler__mdt` record to exist in the org, which they do once you've deployed them.

**Without DML**, faster and independent of the org's configuration: build the trigger context yourself and call the manager with it.

```apex
@IsTest
static void defaultsAreSetOnInsert() {
    List<Account> accounts = new List<Account>{ new Account(Name = 'Acme') };
    TriggerHandlerContext context = new TriggerHandlerContext(System.TriggerOperation.BEFORE_INSERT, accounts, null);

    TriggerHandlerManager.handle('Account', context);

    Assert.areEqual('Prospect', accounts[0].Type);
}
```

This runs every active handler configured for `Account` and `BEFORE_INSERT`, exactly as the trigger would, including ordering, bypasses and the recursion guard.

## Records saved by Flows, the API or other automation

Handlers run the same way whatever saves the record: a user in the UI, an integration through the API, Apex, or a record-triggered Flow. A common case is a Flow that updates the record after it's saved:

1. The user saves the record. The trigger runs your handlers.
2. The after-save Flow updates the same record. The trigger fires again.
3. Your handlers run again, now seeing the Flow's change.

Step 3 is on purpose: the recursion guard only stops a handler that is **still running** on the same records, which is what happens when a handler updates its own records. Once a handler has finished, a later save runs it again. This is checked end to end with a real trigger, a handler that updates its own records and a record-triggered Flow, as an admin and as a standard user.

What it means for your handlers: they can run more than once per transaction on the same record, so they must be idempotent. Compare against `oldMap` and act only when the field you care about actually changed, as in the async pattern above. Don't count on "this only runs once".

## Bypassing handlers

Three ways, from narrowest to widest:

- **From code, for one handler:** `TriggerHandlerManager.bypass('AccountRegionAssignmentHandler')` skips it for the rest of the transaction, until `clearBypass('AccountRegionAssignmentHandler')`. Useful when a service updates records in bulk and doesn't want that handler's side effects. `clearAllBypasses()` resets everything.
- **For some users, for one handler:** put the API name of a custom permission in the handler's `Bypass_Permission__c`. Users who have that permission (through a permission set) skip that handler.
- **For some users, for every handler:** assign the shipped **Bypass Trigger Handlers** permission set. It grants the `Bypass_All_Trigger_Handlers` custom permission, and those users skip every handler. Meant for data migration or integration users only.

A bypass skips your handlers, not the rest of the org's automation: Flows, validation rules and other triggers still run.

## Permissions

Nothing to assign for the framework itself. Triggers run in system context, and `TriggerHandlerManager` reads `Trigger_Handler__mdt` with `getAll()`, which works for every user and doesn't use a SOQL query. Reading a custom metadata type with SOQL, by contrast, fails for users without access to it in orgs that restrict custom metadata, which would break every save those users make.

What your handlers need depends on what they do. A handler declared `with sharing`, or one that queries `WITH USER_MODE`, only sees what the running user can see. Decide that per handler, and test it with `System.runAs` as a standard user.

## What you should NOT do

- Don't put logic directly in a `.trigger` file. The trigger's only job is to call `TriggerHandlerManager.handle(...)`.
- Don't assume a handler runs once per transaction. A Flow, a workflow field update or another handler can save the same records again, and your handler runs again each time. Write it so running twice is harmless.
- Don't skip setting `Is_Active__c = true` and then wonder why nothing runs — an inactive or missing metadata record means the handler is skipped. `validateConfiguration()` reports records that point to missing or broken classes.
- Don't run SOQL or DML directly inside a hook — see the recommended pattern above.
- Don't give the bypass permission set to regular users. It turns off every handler for them.

## Recursion guard, briefly

`TriggerHandlerManager` tracks which record Ids each handler is processing for each event **while it runs**. If the trigger fires again for the same handler, event and records before it finishes (typically because the handler updated the records it's processing), that nested run is skipped. When the handler finishes, or throws, the Ids are released.

So a handler never re-enters itself on the same records, but a later save of those records in the same transaction runs it again. A *different* set of records is never blocked. `before insert` isn't guarded this way, since records don't have an Id yet.
