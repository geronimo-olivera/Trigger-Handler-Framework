/**
 * File Name   :	TriggerHandlerContext.cls
 * Description :	The records and event of one trigger execution, as a plain object. TriggerHandlerManager builds it
 *                  from the live Trigger variables and hands it to each handler. Because it's a plain object, tests
 *                  can build one by hand and drive the whole dispatch (ordering, events, recursion guard, bypasses)
 *                  without DML and without a real trigger in the org.
 **/
public inherited sharing class TriggerHandlerContext {

    public System.TriggerOperation operationType { get; private set; }
    public List<SObject> newList { get; private set; }
    public Map<Id, SObject> newMap { get; private set; }
    public List<SObject> oldList { get; private set; }
    public Map<Id, SObject> oldMap { get; private set; }

    /**
     * @param operationType The trigger event, e.g. AFTER_UPDATE. Null means "not running in a trigger".
     * @param newList Trigger.new: the records being inserted, updated or undeleted. Null for delete events.
     * @param oldList Trigger.old: the records before the change. Null for insert and undelete events.
     */
    public TriggerHandlerContext(System.TriggerOperation operationType, List<SObject> newList, List<SObject> oldList) {
        this.operationType = operationType;
        this.newList = newList;
        this.oldList = oldList;
        this.newMap = toMapWhenIdsExist(newList);
        this.oldMap = toMapWhenIdsExist(oldList);
    }

    /**
     * @return the context of the trigger that's running right now. Its operationType is null outside a trigger.
     */
    public static TriggerHandlerContext fromTrigger() {
        return new TriggerHandlerContext(Trigger.operationType, Trigger.new, Trigger.old);
    }

    /**
     * @return the Ids of the records in this context, or null when they have none yet (before insert).
     */
    public Set<Id> getRecordIds() {
        if (newMap != null) { return newMap.keySet(); }
        if (oldMap != null) { return oldMap.keySet(); }
        return null;
    }

    /**
     * Builds an Id map the way Trigger.newMap does: only when every record already has an Id.
     * @param records The records to index. Can be null.
     * @return the records by Id, or null if records is null, empty, or has records without an Id.
     */
    private static Map<Id, SObject> toMapWhenIdsExist(List<SObject> records) {
        if (records == null || records.isEmpty()) { return null; }
        Map<Id, SObject> byId = new Map<Id, SObject>();
        for (SObject record : records) {
            if (record.Id == null) { return null; }
            byId.put(record.Id, record);
        }
        return byId;
    }
}
