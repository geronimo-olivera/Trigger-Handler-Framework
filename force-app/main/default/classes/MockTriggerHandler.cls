/**
 * File Name   :	MockTriggerHandler.cls
 * Description :	Test-only handler used by TriggerHandlerManagerTest. Records every hook it runs in a shared log,
 *                  and can re-enter the manager or throw on demand to exercise the recursion guard.
 **/
@IsTest
public class MockTriggerHandler extends TriggerHandler {

    /** Every hook call from both mock handlers, as "Handler:EVENT:recordCount", in call order. */
    public static List<String> log = new List<String>();

    /** When set, afterUpdate calls the manager again with this context, like a handler updating its own records. */
    public static TriggerHandlerContext reenterWith;

    /** When true, the next hook call throws, then the flag resets. */
    public static Boolean throwOnNextCall = false;

    public static void reset() {
        log = new List<String>();
        reenterWith = null;
        throwOnNextCall = false;
    }

    public static void record(String handlerName, String event, List<SObject> records) {
        if (throwOnNextCall) {
            throwOnNextCall = false;
            throw new MockHandlerException('Simulated failure in ' + handlerName);
        }
        log.add(handlerName + ':' + event + ':' + (records == null ? 0 : records.size()));
    }

    protected override void beforeInsert(List<SObject> newList) { record('Mock', 'BEFORE_INSERT', newList); }
    protected override void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        record('Mock', 'BEFORE_UPDATE', newList);
        Assert.areEqual(newList.size(), oldMap.size(), 'the old map comes with every update');
    }
    protected override void beforeDelete(List<SObject> oldList) { record('Mock', 'BEFORE_DELETE', oldList); }
    protected override void afterInsert(List<SObject> newList) { record('Mock', 'AFTER_INSERT', newList); }
    protected override void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        record('Mock', 'AFTER_UPDATE', newList);
        if (reenterWith != null) { TriggerHandlerManager.handle('Account', reenterWith); }
    }
    protected override void afterDelete(List<SObject> oldList) { record('Mock', 'AFTER_DELETE', oldList); }
    protected override void afterUndelete(List<SObject> newList) { record('Mock', 'AFTER_UNDELETE', newList); }

    public class MockHandlerException extends Exception {}
}
