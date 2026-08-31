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

4. Create a test class for it. Every handler ships with its own tests — don't rely on `TriggerHandlerManagerTest` to cover your handler's logic, it only tests the manager's dispatch behavior.

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

## What you should NOT do

- Don't put logic directly in a `.trigger` file. The trigger's only job is to call `TriggerHandlerManager.handle(...)`.
- Don't have a handler perform DML on the same records it's currently processing without being aware of the recursion guard in `TriggerHandlerManager` — it blocks a handler from running twice on the *same* record Ids within one transaction, but it's not a substitute for writing bulk-safe, idempotent logic.
- Don't skip setting `Is_Active__c = true` and then wonder why nothing runs — an inactive or missing metadata record means the handler is silently skipped.
- Don't run SOQL or DML directly inside a hook — see the recommended pattern above.

## Recursion guard, briefly

`TriggerHandlerManager` tracks which record Ids each handler has already processed for each event, within the current transaction. If the exact same Ids come through the same handler+event again (e.g. a handler updates the records it's already processing, re-firing the trigger), that second pass is skipped. A *different* set of records — even for the same object and event, later in the same transaction — is not blocked.

`before insert` is never guarded this way, since records don't have an Id yet at that point.
