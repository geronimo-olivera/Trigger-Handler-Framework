# Trigger Handler Framework

A metadata-driven Apex trigger handler framework for Salesforce. Trigger logic is dispatched to handler classes based on `Trigger_Handler__mdt` custom metadata records, with a recursion guard that prevents a handler from running twice on the same records within a transaction.

## Contents

- [`force-app/main/default/classes/TriggerHandler.cls`](force-app/main/default/classes/TriggerHandler.cls) — abstract base class with a hook per trigger event.
- [`force-app/main/default/classes/TriggerHandlerInterface.cls`](force-app/main/default/classes/TriggerHandlerInterface.cls) — contract implemented by every handler.
- [`force-app/main/default/classes/TriggerHandlerManager.cls`](force-app/main/default/classes/TriggerHandlerManager.cls) — looks up active handlers for an object/event and dispatches to them.
- [`force-app/main/default/objects/Trigger_Handler__mdt/`](force-app/main/default/objects/Trigger_Handler__mdt/) — custom metadata type that configures which handler classes run for which object/event.

## Deploy to an org

You need [VS Code with the Salesforce Extension Pack](https://developer.salesforce.com/tools/vscode/) and an authenticated org.

1. Clone this repo and open it in VS Code.
2. Authenticate to your target org (`SFDX: Authorize an Org`, or `sf org login web` from the CLI).
3. Right-click [`manifest/package.xml`](manifest/package.xml) and choose **SFDX: Deploy Source in Manifest to Org**.

That deploys everything the framework needs — Apex classes and the `Trigger_Handler__mdt` custom metadata type with its fields and layout — in one step.

## Documentation

Project-specific documentation lives in [`docs/`](docs/README.md).
