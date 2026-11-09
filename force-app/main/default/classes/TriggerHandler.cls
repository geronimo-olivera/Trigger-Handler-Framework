/**
 * File Name   :	TriggerHandler.cls
 * Description :	Base abstract class for all trigger handlers, providing default hook methods for each trigger event.
 *                  Subclasses can override only the methods they need, keeping trigger logic clean and reusable.
 *                  The records come from TriggerHandlerManager's current context, so the same handler runs the same
 *                  way from a real trigger and from a test that builds a TriggerHandlerContext by hand.
 **/
public abstract inherited sharing class TriggerHandler implements TriggerHandlerInterface {
    /**
     * Executes the appropriate hook method based on the current trigger operation.
     */
    public void execute() {
        TriggerHandlerContext context = TriggerHandlerManager.getCurrentContext();
        if (context == null) { context = TriggerHandlerContext.fromTrigger(); }
        if (context.operationType == null) { return; }
        switch on context.operationType {
            when BEFORE_INSERT  { beforeInsert(context.newList); }
            when BEFORE_UPDATE  { beforeUpdate(context.newList, context.oldMap); }
            when BEFORE_DELETE  { beforeDelete(context.oldList); }
            when AFTER_INSERT   { afterInsert(context.newList); }
            when AFTER_UPDATE   { afterUpdate(context.newList, context.oldMap); }
            when AFTER_DELETE   { afterDelete(context.oldList); }
            when AFTER_UNDELETE { afterUndelete(context.newList); }
        }
    }

    /**
     * Hook for Before Insert logic.
     * @param newList Records being inserted.
     */
    protected virtual void beforeInsert(List<SObject> newList) {}

    /**
     * Hook for Before Update logic.
     * @param newList Updated records.
     * @param oldMap Previous versions of the updated records.
     */
    protected virtual void beforeUpdate(List<SObject> newList, Map<Id,SObject> oldMap) {}

    /**
     * Hook for Before Delete logic.
     * @param oldList Records being deleted.
     */
    protected virtual void beforeDelete(List<SObject> oldList) {}

    /**
     * Hook for After Insert logic.
     * @param newList Records that were inserted.
     */
    protected virtual void afterInsert(List<SObject> newList) {}

    /**
     * Hook for After Update logic.
     * @param newList Updated records after commit.
     * @param oldMap Previous versions of the updated records.
     */
    protected virtual void afterUpdate(List<SObject> newList, Map<Id,SObject> oldMap) {}

    /**
     * Hook for After Delete logic.
     * @param oldList Records that were deleted.
     */
    protected virtual void afterDelete(List<SObject> oldList) {}

    /**
     * Hook for After Undelete logic.
     * @param newList Records that were restored from the Recycle Bin.
     */
    protected virtual void afterUndelete(List<SObject> newList) {}
}