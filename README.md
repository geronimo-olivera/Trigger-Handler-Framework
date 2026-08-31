# Trigger Handler Framework

A metadata-driven Apex trigger handler framework for Salesforce. Trigger logic is dispatched to handler classes based on `Trigger_Handler__mdt` custom metadata records, with a recursion guard that prevents a handler from running twice on the same records within a transaction.

## Purpose

Salesforce orgs tend to accumulate triggers with logic written directly inside them, duplicated across objects, with no consistent way to enable/disable/reorder behavior without a deploy. The goal of this framework is:

- **One trigger per object**, with zero logic in it — it only calls into the manager.
- **Handler classes** contain the actual logic, one class per concern, each overriding only the events it cares about.
- **Configuration over code** — which handlers run, for which object, for which events (before/after insert/update/delete/undelete), and in what order, lives in `Trigger_Handler__mdt` records. Turning a handler on/off or reordering it doesn't require touching Apex.
- **Safe by default** — a built-in recursion guard stops a handler from processing the same records twice within one transaction.

See [`docs/USAGE.md`](docs/USAGE.md) for how to add a new handler and what to avoid.

## Contents

- [`force-app/main/default/classes/TriggerHandler.cls`](force-app/main/default/classes/TriggerHandler.cls) — abstract base class with a hook per trigger event (`beforeInsert`, `afterUpdate`, etc.), all empty by default so a subclass only overrides what it needs.
- [`force-app/main/default/classes/TriggerHandlerInterface.cls`](force-app/main/default/classes/TriggerHandlerInterface.cls) — contract implemented by every handler.
- [`force-app/main/default/classes/TriggerHandlerManager.cls`](force-app/main/default/classes/TriggerHandlerManager.cls) — looks up active handlers for an object/event from `Trigger_Handler__mdt`, applies the recursion guard, and dispatches to them.
- [`force-app/main/default/classes/MockTriggerHandler.cls`](force-app/main/default/classes/MockTriggerHandler.cls) — test-only handler used by `TriggerHandlerManagerTest`.
- [`force-app/main/default/objects/Trigger_Handler__mdt/`](force-app/main/default/objects/Trigger_Handler__mdt/) — custom metadata type that configures which handler classes run for which object/event.

## Custom metadata: `Trigger_Handler__mdt`

Each record configures one handler class for one object.

| Field | Type | Description |
|---|---|---|
| `Class_Name__c` | Text (required, unique) | API name of the Apex class to invoke. Must implement `TriggerHandlerInterface` (in practice, extend `TriggerHandler`). |
| `Object__c` | Text (required) | API name of the SObject this handler applies to (e.g. `Account`). |
| `Is_Active__c` | Checkbox | Must be `true` for the handler to run at all. An inactive or missing record means the handler is silently skipped. |
| `Order__c` | Number (required) | Execution order relative to other active handlers on the same object/event. |
| `Before_Insert__c` | Checkbox | Run this handler's `beforeInsert` hook. |
| `After_Insert__c` | Checkbox | Run this handler's `afterInsert` hook. |
| `Before_Update__c` | Checkbox | Run this handler's `beforeUpdate` hook. |
| `After_Update__c` | Checkbox | Run this handler's `afterUpdate` hook. |
| `Before_Delete__c` | Checkbox | Run this handler's `beforeDelete` hook. |
| `After_Delete__c` | Checkbox | Run this handler's `afterDelete` hook. |
| `After_Undelete__c` | Checkbox | Run this handler's `afterUndelete` hook. |

## Tests

`TriggerHandlerManagerTest` covers what's reachable without performing DML (this repo intentionally ships no trigger wired to a real object — see below):

- **`handleReturnsEarlyForBlankOrNullObjectName`** — confirms `handle()` no-ops safely when called with a blank or null object name.
- **`handleDoesNothingWithoutActiveTriggerContext`** — confirms that calling `handle()` outside of an actual trigger execution (no `Trigger.operationType`) matches no context and runs no handler, instead of throwing or executing anything unexpected.

The dispatch logic itself (recursion guard, class resolution, hook execution) can only be exercised through DML against a real trigger — see [`docs/USAGE.md`](docs/USAGE.md) for how to wire one up in your own org if you want to extend coverage there.

## Deploy to an org

You need [VS Code with the Salesforce Extension Pack](https://developer.salesforce.com/tools/vscode/) and an authenticated org.

1. Clone this repo and open it in VS Code.
2. Authenticate to your target org (`SFDX: Authorize an Org`, or `sf org login web` from the CLI).
3. Right-click [`manifest/package.xml`](manifest/package.xml) and choose **SFDX: Deploy Source in Manifest to Org**.

That deploys everything the framework needs — Apex classes and the `Trigger_Handler__mdt` custom metadata type with its fields and layout — in one step.

## Documentation

- [`docs/USAGE.md`](docs/USAGE.md) — how to add a handler, what to avoid, how the recursion guard works.
