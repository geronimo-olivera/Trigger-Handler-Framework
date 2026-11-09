/**
 * File Name   :	TriggerHandlerManagerTest.cls
 * Description :	Tests the manager's dispatch end to end without DML: each test builds a TriggerHandlerContext by
 *                  hand and supplies its own Trigger_Handler__mdt records, so it doesn't depend on any trigger,
 *                  handler or configuration in the org. activeConfigurationInThisOrgIsValid is the exception: it
 *                  checks the real configuration, so a typo in a Trigger_Handler__mdt record fails the deploy.
 **/
@IsTest
private class TriggerHandlerManagerTest {

    private static final Id ACCOUNT_A = '001000000000001AAA';
    private static final Id ACCOUNT_B = '001000000000002AAA';
    private static final Id ACCOUNT_C = '001000000000003AAA';

    private static Trigger_Handler__mdt handlerConfig(String className, Decimal order) {
        return new Trigger_Handler__mdt(
            DeveloperName = className.left(40),
            MasterLabel = className.left(40),
            Class_Name__c = className,
            Object__c = 'Account',
            Order__c = order,
            Is_Active__c = true,
            Before_Insert__c = true,
            Before_Update__c = true,
            Before_Delete__c = true,
            After_Insert__c = true,
            After_Update__c = true,
            After_Delete__c = true,
            After_Undelete__c = true
        );
    }

    private static List<Account> accounts(List<Id> ids) {
        List<Account> records = new List<Account>();
        for (Id accountId : ids) { records.add(new Account(Id = accountId, Name = 'Account ' + accountId)); }
        return records;
    }

    private static TriggerHandlerContext afterUpdate(List<Id> ids) {
        return new TriggerHandlerContext(System.TriggerOperation.AFTER_UPDATE, accounts(ids), accounts(ids));
    }

    private static void useHandlers(List<Trigger_Handler__mdt> handlers) {
        TriggerHandlerManager.handlersOverride = handlers;
        MockTriggerHandler.reset();
    }

    private static User createStandardUser() {
        List<Profile> profiles = [
            SELECT Id, Name FROM Profile
            WHERE UserLicense.Name = 'Salesforce' AND PermissionsModifyAllData = false
            AND PermissionsViewAllData = false AND PermissionsCustomizeApplication = false
            ORDER BY Name
        ];
        Profile chosen = profiles[0];
        for (Profile candidate : profiles) {
            if (candidate.Name == 'Standard User' || candidate.Name == 'Usuario estándar') { chosen = candidate; break; }
        }
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User user = new User(
            ProfileId = chosen.Id, FirstName = 'Standard', LastName = 'Tester', Alias = 'stdtst',
            Email = 'standard.tester@example.com', Username = 'standard.tester.' + unique + '@example.com',
            TimeZoneSidKey = 'America/Montevideo', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert user;
        return user;
    }

    @IsTest
    static void eachEventRunsItsHookWithTheRightRecords() {
        useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockTriggerHandler', 1) });
        List<Account> withoutIds = new List<Account>{ new Account(Name = 'New'), new Account(Name = 'New 2') };
        List<Account> withIds = accounts(new List<Id>{ ACCOUNT_A, ACCOUNT_B });

        TriggerHandlerManager.handle('Account', new TriggerHandlerContext(System.TriggerOperation.BEFORE_INSERT, withoutIds, null));
        TriggerHandlerManager.handle('Account', new TriggerHandlerContext(System.TriggerOperation.AFTER_INSERT, withIds, null));
        TriggerHandlerManager.handle('Account', new TriggerHandlerContext(System.TriggerOperation.BEFORE_UPDATE, withIds, withIds));
        TriggerHandlerManager.handle('Account', new TriggerHandlerContext(System.TriggerOperation.AFTER_UPDATE, withIds, withIds));
        TriggerHandlerManager.handle('Account', new TriggerHandlerContext(System.TriggerOperation.BEFORE_DELETE, null, withIds));
        TriggerHandlerManager.handle('Account', new TriggerHandlerContext(System.TriggerOperation.AFTER_DELETE, null, withIds));
        TriggerHandlerManager.handle('Account', new TriggerHandlerContext(System.TriggerOperation.AFTER_UNDELETE, withIds, null));

        Assert.areEqual(new List<String>{
            'Mock:BEFORE_INSERT:2', 'Mock:AFTER_INSERT:2', 'Mock:BEFORE_UPDATE:2', 'Mock:AFTER_UPDATE:2',
            'Mock:BEFORE_DELETE:2', 'Mock:AFTER_DELETE:2', 'Mock:AFTER_UNDELETE:2'
        }, MockTriggerHandler.log, 'every event reaches its own hook with its records');
        Assert.isNull(TriggerHandlerManager.getCurrentContext(), 'no context is left behind after the handlers finish');
    }

    @IsTest
    static void hooksAHandlerDoesNotOverrideDoNothing() {
        useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockSecondTriggerHandler', 1) });
        List<Account> withIds = accounts(new List<Id>{ ACCOUNT_A });

        for (System.TriggerOperation operation : System.TriggerOperation.values()) {
            Boolean isDelete = operation == System.TriggerOperation.BEFORE_DELETE || operation == System.TriggerOperation.AFTER_DELETE;
            Boolean isInsert = operation == System.TriggerOperation.BEFORE_INSERT || operation == System.TriggerOperation.AFTER_INSERT || operation == System.TriggerOperation.AFTER_UNDELETE;
            TriggerHandlerManager.handle('Account', new TriggerHandlerContext(operation, isDelete ? null : withIds, isInsert ? null : withIds));
        }

        Assert.areEqual(new List<String>{ 'Second:AFTER_UPDATE:1' }, MockTriggerHandler.log, 'only the overridden hook does anything');
    }

    @IsTest
    static void handlersRunInOrderOnlyForTheirObjectAndEvents() {
        Trigger_Handler__mdt first = handlerConfig('MockSecondTriggerHandler', 1);
        Trigger_Handler__mdt second = handlerConfig('MockTriggerHandler', 2);
        Trigger_Handler__mdt inactive = handlerConfig('MockTriggerHandler', 0);
        inactive.Is_Active__c = false;
        Trigger_Handler__mdt otherObject = handlerConfig('MockTriggerHandler', 0);
        otherObject.Object__c = 'Contact';
        Trigger_Handler__mdt otherEvent = handlerConfig('MockTriggerHandler', 0);
        otherEvent.After_Update__c = false;
        useHandlers(new List<Trigger_Handler__mdt>{ second, inactive, otherObject, otherEvent, first });

        TriggerHandlerManager.handle('account', afterUpdate(new List<Id>{ ACCOUNT_A }));

        Assert.areEqual(new List<String>{ 'Second:AFTER_UPDATE:1', 'Mock:AFTER_UPDATE:1' }, MockTriggerHandler.log,
            'active handlers run by Order__c; inactive ones and ones for another object or event are skipped; the object name is case-insensitive');
    }

    @IsTest
    static void reentryOnTheSameRecordsIsSkipped() {
        useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockTriggerHandler', 1) });
        TriggerHandlerContext context = afterUpdate(new List<Id>{ ACCOUNT_A, ACCOUNT_B });
        MockTriggerHandler.reenterWith = context;

        TriggerHandlerManager.handle('Account', context);

        Assert.areEqual(1, MockTriggerHandler.log.size(), 'a handler that updates its own records does not run again inside itself');
    }

    @IsTest
    static void aLaterSaveOfTheSameRecordsRunsAgain() {
        useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockTriggerHandler', 1) });

        TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));
        TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));

        Assert.areEqual(2, MockTriggerHandler.log.size(),
            'once the first run finished, a new save of the same record (e.g. a record-triggered Flow updating it) runs the handler again');
    }

    @IsTest
    static void reentryWithOtherRecordsRuns() {
        useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockTriggerHandler', 1) });
        MockTriggerHandler.reenterWith = afterUpdate(new List<Id>{ ACCOUNT_C });

        TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));

        Assert.areEqual(new List<String>{ 'Mock:AFTER_UPDATE:1', 'Mock:AFTER_UPDATE:1' }, MockTriggerHandler.log,
            'different records run, and the nested run stops itself when it re-enters with its own records');
    }

    @IsTest
    static void theGuardIsReleasedWhenAHandlerThrows() {
        useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockTriggerHandler', 1) });
        MockTriggerHandler.throwOnNextCall = true;

        try {
            TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));
            Assert.fail('the handler exception should reach the caller, so the save shows the error');
        } catch (MockTriggerHandler.MockHandlerException ex) {
            Assert.isTrue(ex.getMessage().contains('Simulated failure'), 'the original exception is not swallowed');
        }
        Assert.isNull(TriggerHandlerManager.getCurrentContext(), 'the context is cleared even after an exception');

        TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));
        Assert.areEqual(1, MockTriggerHandler.log.size(), 'the record is not left marked as in progress after the failure');
    }

    @IsTest
    static void handlersCanBeBypassedFromCode() {
        useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockTriggerHandler', 1), handlerConfig('MockSecondTriggerHandler', 2) });

        TriggerHandlerManager.bypass('MockTriggerHandler');
        Assert.isTrue(TriggerHandlerManager.isBypassed('mocktriggerhandler'), 'bypasses ignore case');
        TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));
        Assert.areEqual(new List<String>{ 'Second:AFTER_UPDATE:1' }, MockTriggerHandler.log, 'only the bypassed handler is skipped');

        TriggerHandlerManager.clearBypass('MockTriggerHandler');
        TriggerHandlerManager.bypass('MockSecondTriggerHandler');
        TriggerHandlerManager.clearAllBypasses();
        MockTriggerHandler.reset();
        TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_B }));
        Assert.areEqual(2, MockTriggerHandler.log.size(), 'clearing bypasses brings both handlers back');

        TriggerHandlerManager.bypass(null);
        TriggerHandlerManager.clearBypass('');
        Assert.isFalse(TriggerHandlerManager.isBypassed((String) null), 'blank names are ignored');
    }

    @IsTest
    static void usersWithTheBypassPermissionSkipEveryHandler() {
        User migrationUser = createStandardUser();
        PermissionSet bypassSet = [SELECT Id FROM PermissionSet WHERE Name = 'Bypass_Trigger_Handlers'];
        insert new PermissionSetAssignment(AssigneeId = migrationUser.Id, PermissionSetId = bypassSet.Id);
        useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockTriggerHandler', 1) });

        System.runAs(migrationUser) {
            TriggerHandlerManager.resetUserBypassCache();
            TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));
        }

        Assert.isTrue(MockTriggerHandler.log.isEmpty(), 'a user with Bypass_All_Trigger_Handlers runs no handler');
    }

    @IsTest
    static void aHandlerCanBeSkippedForUsersWithItsOwnPermission() {
        User integrationUser = createStandardUser();
        PermissionSet bypassSet = [SELECT Id FROM PermissionSet WHERE Name = 'Bypass_Trigger_Handlers'];
        insert new PermissionSetAssignment(AssigneeId = integrationUser.Id, PermissionSetId = bypassSet.Id);
        Trigger_Handler__mdt skipped = handlerConfig('MockTriggerHandler', 1);
        skipped.Bypass_Permission__c = TriggerHandlerManager.BYPASS_ALL_PERMISSION;
        Trigger_Handler__mdt kept = handlerConfig('MockSecondTriggerHandler', 2);
        kept.Bypass_Permission__c = 'Permission_Nobody_Has';
        useHandlers(new List<Trigger_Handler__mdt>{ skipped, kept });

        System.runAs(integrationUser) {
            // Leave the global bypass off to test the per-handler check on its own.
            TriggerHandlerManager.bypassAllForUser = false;
            TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));
        }

        Assert.areEqual(new List<String>{ 'Second:AFTER_UPDATE:1' }, MockTriggerHandler.log,
            'the handler whose Bypass_Permission__c the user has is skipped; one naming a permission they lack still runs');
    }

    @IsTest
    static void aStandardUserRunsHandlersAndTheRealConfiguration() {
        User standardUser = createStandardUser();
        System.runAs(standardUser) {
            TriggerHandlerManager.resetUserBypassCache();
            useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockTriggerHandler', 1) });
            TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));
            Assert.areEqual(1, MockTriggerHandler.log.size(), 'a user without admin permissions runs handlers normally');

            TriggerHandlerManager.handlersOverride = null;
            TriggerHandlerManager.handle('Mock_Object_Without_Handlers__c', afterUpdate(new List<Id>{ ACCOUNT_A }));
            Assert.isNotNull(TriggerHandlerManager.validateConfiguration(), 'and can read Trigger_Handler__mdt');
        }
    }

    @IsTest
    static void unusableClassesAreSkippedAtRuntime() {
        useHandlers(new List<Trigger_Handler__mdt>{
            handlerConfig('ClassThatDoesNotExist', 1),
            handlerConfig('TriggerHandlerManager', 2),
            handlerConfig('TriggerHandlerContext', 3),
            handlerConfig('MockTriggerHandler', 4)
        });

        TriggerHandlerManager.handle('Account', afterUpdate(new List<Id>{ ACCOUNT_A }));

        Assert.areEqual(new List<String>{ 'Mock:AFTER_UPDATE:1' }, MockTriggerHandler.log,
            'a missing class, a class that is not a handler and one without a no-argument constructor are skipped, not thrown');
    }

    @IsTest
    static void validateConfigurationReportsEveryProblem() {
        Trigger_Handler__mdt missingClass = handlerConfig('ClassThatDoesNotExist', 1);
        Trigger_Handler__mdt notAHandler = handlerConfig('TriggerHandlerManager', 2);
        Trigger_Handler__mdt noConstructor = handlerConfig('TriggerHandlerContext', 3);
        Trigger_Handler__mdt missingObject = handlerConfig('MockTriggerHandler', 4);
        missingObject.Object__c = 'Object_That_Does_Not_Exist__c';
        Trigger_Handler__mdt noEvents = handlerConfig('MockSecondTriggerHandler', 5);
        for (SObjectField field : new List<SObjectField>{
            Trigger_Handler__mdt.Before_Insert__c, Trigger_Handler__mdt.Before_Update__c, Trigger_Handler__mdt.Before_Delete__c,
            Trigger_Handler__mdt.After_Insert__c, Trigger_Handler__mdt.After_Update__c, Trigger_Handler__mdt.After_Delete__c,
            Trigger_Handler__mdt.After_Undelete__c
        }) {
            noEvents.put(field, false);
        }
        Trigger_Handler__mdt valid = handlerConfig('MockTriggerHandler', 6);
        useHandlers(new List<Trigger_Handler__mdt>{ missingClass, notAHandler, noConstructor, missingObject, noEvents, valid });

        List<String> problems = TriggerHandlerManager.validateConfiguration();

        Assert.areEqual(5, problems.size(), 'one problem per misconfigured record, none for the valid one: ' + problems);
        String all = String.join(problems, '\n');
        Assert.isTrue(all.contains('does not exist or is not visible'), 'a missing class is reported');
        Assert.isTrue(all.contains('does not implement TriggerHandlerInterface'), 'a class that is not a handler is reported');
        Assert.isTrue(all.contains('no arguments'), 'a class without a no-argument constructor is reported');
        Assert.isTrue(all.contains('Object_That_Does_Not_Exist__c'), 'a missing object is reported');
        Assert.isTrue(all.contains('no event is selected'), 'a record with no events is reported');
    }

    @IsTest
    static void activeConfigurationInThisOrgIsValid() {
        List<String> problems = TriggerHandlerManager.validateConfiguration();
        Assert.isTrue(problems.isEmpty(), 'Fix these Trigger_Handler__mdt records: ' + String.join(problems, ' | '));
    }

    @IsTest
    static void nothingRunsOutsideATriggerOrWithoutAnObject() {
        useHandlers(new List<Trigger_Handler__mdt>{ handlerConfig('MockTriggerHandler', 1) });

        TriggerHandlerManager.handle('');
        TriggerHandlerManager.handle(null);
        TriggerHandlerManager.handle('Account');
        TriggerHandlerManager.handle('Account', null);
        TriggerHandlerManager.handle('Account', new TriggerHandlerContext(null, accounts(new List<Id>{ ACCOUNT_A }), null));
        new MockTriggerHandler().execute();

        Assert.isTrue(MockTriggerHandler.log.isEmpty(), 'without a trigger event, no hook runs');
        Assert.isNull(TriggerHandlerContext.fromTrigger().getRecordIds(), 'outside a trigger there are no records');
    }
}
