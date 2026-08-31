@isTest
private class TriggerHandlerManagerTest {

    @isTest
    static void handleReturnsEarlyForBlankOrNullObjectName() {
        Test.startTest();
        TriggerHandlerManager.handle('');
        TriggerHandlerManager.handle(null);
        Test.stopTest();
    }

    @isTest
    static void handleDoesNothingOutsideTriggerContext() {
        MockTriggerHandler.resetCounts();

        Test.startTest();
        TriggerHandlerManager.handle('Account');
        Test.stopTest();

        Assert.areEqual(0, MockTriggerHandler.afterInsertCount, 'Called outside a trigger, Trigger.operationType is null, so no context matches and nothing should execute.');
    }

    @isTest
    static void handleRunsBeforeAndAfterInsertOnce() {
        MockTriggerHandler.resetCounts();

        Test.startTest();
        insert new Account(Name = 'Insert Test');
        Test.stopTest();

        Assert.areEqual(1, MockTriggerHandler.beforeInsertCount, 'beforeInsert should run once for a single insert.');
        Assert.areEqual(1, MockTriggerHandler.afterInsertCount, 'afterInsert should run once for a single insert.');
    }

    @isTest
    static void handleRunsForEachSeparateInsertInTheSameTransaction() {
        MockTriggerHandler.resetCounts();

        Test.startTest();
        insert new Account(Name = 'Batch A');
        insert new Account(Name = 'Batch B');
        Test.stopTest();

        Assert.areEqual(2, MockTriggerHandler.afterInsertCount, 'Two separate inserts with different Ids must both run the handler, even within the same transaction.');
    }

    @isTest
    static void handleRunsBeforeAndAfterUpdateOnce() {
        Account account = new Account(Name = 'Update Test');
        insert account;
        MockTriggerHandler.resetCounts();

        Test.startTest();
        account.Name = 'Update Test Changed';
        update account;
        Test.stopTest();

        Assert.areEqual(1, MockTriggerHandler.beforeUpdateCount, 'beforeUpdate should run once.');
        Assert.areEqual(1, MockTriggerHandler.afterUpdateCount, 'afterUpdate should run once.');
    }

    @isTest
    static void handleBlocksSameRecordReenteringSameEvent() {
        Account account = new Account(Name = 'Recursion Test');
        insert account;
        MockTriggerHandler.resetCounts();

        Test.startTest();
        account.Name = 'First Update';
        update account;
        account.Name = 'Second Update';
        update account;
        Test.stopTest();

        Assert.areEqual(1, MockTriggerHandler.afterUpdateCount, 'A second update on the same Id within the same transaction must be blocked by the recursion guard.');
    }

    @isTest
    static void handleRunsBeforeAndAfterDelete() {
        Account account = new Account(Name = 'Delete Test');
        insert account;
        MockTriggerHandler.resetCounts();

        Test.startTest();
        delete account;
        Test.stopTest();

        Assert.areEqual(1, MockTriggerHandler.beforeDeleteCount, 'beforeDelete should run once.');
        Assert.areEqual(1, MockTriggerHandler.afterDeleteCount, 'afterDelete should run once.');
    }

    @isTest
    static void handleRunsAfterUndelete() {
        Account account = new Account(Name = 'Undelete Test');
        insert account;
        delete account;
        MockTriggerHandler.resetCounts();

        Test.startTest();
        undelete account;
        Test.stopTest();

        Assert.areEqual(1, MockTriggerHandler.afterUndeleteCount, 'afterUndelete should run once.');
    }
}
