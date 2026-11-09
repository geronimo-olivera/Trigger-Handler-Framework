# Trigger Handler Framework

A metadata-driven Apex trigger handler framework for Salesforce. Trigger logic is dispatched to handler classes based on `Trigger_Handler__mdt` custom metadata records, with a recursion guard that stops a handler from re-entering itself on the same records, and bypasses by code or by user permission. It works the same for every user, from the UI, the API or a Flow.

[![Deploy to Salesforce](https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png)](https://githubsfdeploy.herokuapp.com?owner=geronimo-olivera&repo=Trigger-Handler-Framework&ref=master)

## Purpose

Salesforce orgs tend to accumulate triggers with logic written directly inside them, duplicated across objects, with no consistent way to enable/disable/reorder behavior without a deploy. The goal of this framework is:

- **One trigger per object**, with zero logic in it — it only calls into the manager.
- **Handler classes** contain the actual logic, one class per concern, each overriding only the events it cares about.
- **Configuration over code** — which handlers run, for which object, for which events (before/after insert/update/delete/undelete), and in what order, lives in `Trigger_Handler__mdt` records. Turning a handler on/off or reordering it doesn't require touching Apex.
- **Safe by default** — a recursion guard skips a handler only while it's already running on the same records. A later save in the same transaction, such as a record-triggered Flow updating the record, runs it again, so it always sees the latest data.
- **Works for every user** — the configuration is read with `Trigger_Handler__mdt.getAll()`, which needs no permission and no SOQL query, so it works the same in a real trigger and in a test running as a standard user.
- **Bypasses when you need them** — skip a handler from code, skip one for users with a custom permission, or skip all of them for a data migration user.

See [`docs/USAGE.md`](docs/USAGE.md) for how to add a new handler and what to avoid.

## Contents

- [`force-app/main/default/classes/TriggerHandler.cls`](force-app/main/default/classes/TriggerHandler.cls) — abstract base class with a hook per trigger event (`beforeInsert`, `afterUpdate`, etc.), all empty by default so a subclass only overrides what it needs.
- [`force-app/main/default/classes/TriggerHandlerInterface.cls`](force-app/main/default/classes/TriggerHandlerInterface.cls) — contract implemented by every handler.
- [`force-app/main/default/classes/TriggerHandlerManager.cls`](force-app/main/default/classes/TriggerHandlerManager.cls) — looks up active handlers for an object/event from `Trigger_Handler__mdt`, applies bypasses and the recursion guard, and dispatches to them. Also has `validateConfiguration()` to find misconfigured records.
- [`force-app/main/default/classes/TriggerHandlerContext.cls`](force-app/main/default/classes/TriggerHandlerContext.cls) — the event and records of one trigger run, as a plain object, so tests can drive the whole dispatch without DML.
- [`force-app/main/default/classes/MockTriggerHandler.cls`](force-app/main/default/classes/MockTriggerHandler.cls) and [`MockSecondTriggerHandler.cls`](force-app/main/default/classes/MockSecondTriggerHandler.cls) — test-only handlers used by `TriggerHandlerManagerTest`.
- [`force-app/main/default/objects/Trigger_Handler__mdt/`](force-app/main/default/objects/Trigger_Handler__mdt/) — custom metadata type that configures which handler classes run for which object/event.
- [`force-app/main/default/customPermissions/`](force-app/main/default/customPermissions/) and [`permissionsets/`](force-app/main/default/permissionsets/) — the `Bypass_All_Trigger_Handlers` custom permission and the `Bypass Trigger Handlers` permission set that grants it.

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
| `Bypass_Permission__c` | Text | Optional API name of a custom permission. Users who have it skip this handler. |

## Permissions

Nothing to assign for the framework to work: triggers run in system context, and the configuration is read with `getAll()`, which every user can use. Standard users, integration users and Flows all run handlers the same way an admin does. What your own handlers need depends on what they do (for example, a handler declared `with sharing` only sees the records the user can see).

The only permission it ships is optional: assign the **Bypass Trigger Handlers** permission set to a data migration or integration user to skip every handler for that user.

## Tests

`TriggerHandlerManagerTest` drives the real dispatch without DML: each test builds a `TriggerHandlerContext` by hand and supplies its own `Trigger_Handler__mdt` records, so it doesn't depend on any trigger or configuration in your org. Its 15 tests cover every event, ordering, inactive records, the recursion guard (re-entry, a later save, an exception in the middle), bypasses by code and by permission, a standard user, and handler classes that are missing or invalid. Coverage is 95% on `TriggerHandlerManager`, 95% on `TriggerHandler` and 100% on `TriggerHandlerContext`.

One test, `activeConfigurationInThisOrgIsValid`, checks **your** real configuration with `validateConfiguration()`. If a `Trigger_Handler__mdt` record points to a class that doesn't exist or doesn't compile, it fails with the record's name, so the problem shows up at deploy time instead of being skipped in production.

It was also checked end to end in a scratch org with a real trigger, a handler that updates its own records and a record-triggered Flow, as an admin, as a standard user and as a user with the bypass permission, and with 250 records in one transaction. To run the tests in a scratch org:

```bash
sf org create scratch --definition-file config/project-scratch-def.json --alias thf --duration-days 1 --target-dev-hub <your-dev-hub>
sf project deploy start --manifest manifest/package.xml --target-org thf
sf apex run test --target-org thf --test-level RunLocalTests --code-coverage --wait 20
```

## Deploy to an org

### One click

[![Deploy to Salesforce](https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png)](https://githubsfdeploy.herokuapp.com?owner=geronimo-olivera&repo=Trigger-Handler-Framework&ref=master)

Click the button, choose production or sandbox, and log in to the org. The deploy runs through [GitHub Salesforce Deploy](https://github.com/afawcett/githubsfdeploy), a free open-source tool by Andrew Fawcett. Try it in a sandbox first: a production deploy also runs your org's Apex tests.

### From VS Code

You need [VS Code with the Salesforce Extension Pack](https://developer.salesforce.com/tools/vscode/) and an authenticated org.

1. Clone this repo and open it in VS Code.
2. Authenticate to your target org (`SFDX: Authorize an Org`, or `sf org login web` from the CLI).
3. Right-click [`manifest/package.xml`](manifest/package.xml) and choose **SFDX: Deploy Source in Manifest to Org**.

That deploys everything the framework needs — Apex classes, the `Trigger_Handler__mdt` custom metadata type with its fields and layout, and the optional bypass permission — in one step.

## Documentation

- [`docs/USAGE.md`](docs/USAGE.md) — how to add a handler, test it, bypass it, use it with Flows, and how the recursion guard works.

## License

Released under the [MIT License](LICENSE).
