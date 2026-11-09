/**
 * File Name   :	MockSecondTriggerHandler.cls
 * Description :	Second test-only handler, so TriggerHandlerManagerTest can check the order handlers run in.
 **/
@IsTest
public class MockSecondTriggerHandler extends TriggerHandler {
    protected override void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        MockTriggerHandler.record('Second', 'AFTER_UPDATE', newList);
    }
}
