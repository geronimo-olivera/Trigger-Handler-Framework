/**
 * File Name   :	TriggerHandlerManager.cls
 * Description :	Runs the trigger handlers configured in Trigger_Handler__mdt for an object and event, in order.
 *                  Call TriggerHandlerManager.handle('ObjectApiName') from the object's single trigger.
 *
 *                  Recursion guard: a handler is skipped only while it is already running on the same records,
 *                  e.g. when it updates the records it's processing and that update re-fires the trigger. Once it
 *                  finishes, a later save of the same records in the same transaction (a record-triggered Flow, a
 *                  workflow field update, another handler) runs it again, so it always sees the latest changes.
 *
 *                  Bypasses: a handler can be skipped from code (bypass), for users with the
 *                  Bypass_All_Trigger_Handlers custom permission, or for users with the custom permission named in
 *                  its own Bypass_Permission__c field.
 **/
public inherited sharing class TriggerHandlerManager {

    /** Custom permission that skips every handler for the users who have it, e.g. a data migration user. */
    public static final String BYPASS_ALL_PERMISSION = 'Bypass_All_Trigger_Handlers';

    /** Record Ids each running handler is processing, by "ClassName:OPERATION". Entries are removed when it finishes. */
    private static Map<String, Set<Id>> inProgressIdsByHandler = new Map<String, Set<Id>>();

    /** Handler class names skipped from code for the rest of the transaction, or until clearBypass. */
    private static Set<String> bypassedHandlers = new Set<String>();

    /** The context of the handler running right now. Handlers read it through TriggerHandler. */
    private static TriggerHandlerContext currentContext;

    /** Cached result of the Bypass_All_Trigger_Handlers check, per transaction. */
    @TestVisible
    private static Boolean bypassAllForUser;

    /** Lets a test choose the handlers to run instead of reading Trigger_Handler__mdt. Null in real use. */
    @TestVisible
    private static List<Trigger_Handler__mdt> handlersOverride;

    /**
     * Runs the active handlers for this object and the current trigger event. Does nothing outside a trigger.
     * @param objectName The API name of the SObject, e.g. 'Account'.
     */
    public static void handle(String objectName) {
        handle(objectName, TriggerHandlerContext.fromTrigger());
    }

    /**
     * Runs the active handlers for this object and the given context. Public so tests, and code that simulates a
     * trigger, can drive the dispatch without DML.
     * @param objectName The API name of the SObject, e.g. 'Account'.
     * @param context The event and records to run the handlers with.
     */
    public static void handle(String objectName, TriggerHandlerContext context) {
        if (String.isBlank(objectName) || context == null || context.operationType == null) { return; }
        if (isBypassAllForUser()) { return; }

        for (Trigger_Handler__mdt handler : getHandlers(objectName)) {
            if (!matchesEvent(handler, context.operationType)) { continue; }
            if (isBypassed(handler)) { continue; }
            runHandler(handler, context);
        }
    }

    /**
     * Skips a handler for the rest of the transaction, e.g. while a service updates records in bulk and the handler's
     * work isn't wanted. Call clearBypass when done.
     * @param className The handler's class name.
     */
    public static void bypass(String className) {
        if (String.isNotBlank(className)) { bypassedHandlers.add(className.toLowerCase()); }
    }

    /**
     * Stops skipping a handler that was bypassed from code.
     * @param className The handler's class name.
     */
    public static void clearBypass(String className) {
        if (String.isNotBlank(className)) { bypassedHandlers.remove(className.toLowerCase()); }
    }

    /**
     * Stops skipping every handler that was bypassed from code.
     */
    public static void clearAllBypasses() {
        bypassedHandlers.clear();
    }

    /**
     * @param className The handler's class name.
     * @return true if the handler is bypassed from code.
     */
    public static Boolean isBypassed(String className) {
        return String.isNotBlank(className) && bypassedHandlers.contains(className.toLowerCase());
    }

    /**
     * @return the context of the handler running right now, or null outside a handler.
     */
    public static TriggerHandlerContext getCurrentContext() {
        return currentContext;
    }

    /**
     * Checks every active Trigger_Handler__mdt record and reports what would make it fail or be skipped at runtime:
     * a class that doesn't exist, doesn't compile or doesn't implement TriggerHandlerInterface, an object that doesn't
     * exist, or a record with no event selected. Call it from a test in your org so a typo fails the deploy instead of being
     * skipped silently in production.
     * @return one readable problem per misconfigured record. Empty when everything is valid.
     */
    public static List<String> validateConfiguration() {
        List<String> problems = new List<String>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (Trigger_Handler__mdt handler : queryActiveHandlers(null)) {
            String label = handler.DeveloperName + ' (' + handler.Class_Name__c + ')';
            if (String.isBlank(handler.Object__c) || !globalDescribe.containsKey(handler.Object__c.toLowerCase())) {
                problems.add(label + ': object "' + handler.Object__c + '" does not exist.');
            }
            Type classType;
            String loadError;
            try {
                classType = Type.forName(handler.Class_Name__c);
            } catch (Exception ex) {
                loadError = ex.getMessage();
            }
            if (loadError != null) {
                problems.add(label + ': class "' + handler.Class_Name__c + '" does not compile: ' + loadError);
            } else if (classType == null) {
                problems.add(label + ': class "' + handler.Class_Name__c + '" does not exist or is not visible.');
            } else if (newInstanceOrNull(classType) == null) {
                problems.add(label + ': class "' + handler.Class_Name__c + '" needs a public constructor with no arguments.');
            } else if (!(newInstanceOrNull(classType) instanceof TriggerHandlerInterface)) {
                problems.add(label + ': class "' + handler.Class_Name__c + '" does not implement TriggerHandlerInterface.');
            }
            if (!handlesAnyEvent(handler)) {
                problems.add(label + ': no event is selected, so it never runs.');
            }
        }
        return problems;
    }

    /**
     * Runs one handler with the recursion guard, restoring the previous context afterwards even if it throws.
     * @param handler The handler's configuration.
     * @param context The event and records to run it with.
     */
    private static void runHandler(Trigger_Handler__mdt handler, TriggerHandlerContext context) {
        String handlerKey = handler.Class_Name__c.toLowerCase() + ':' + context.operationType;
        Set<Id> recordIds = context.getRecordIds();
        Set<Id> inProgress = inProgressIdsByHandler.get(handlerKey);
        if (recordIds != null && inProgress != null && inProgress.containsAll(recordIds)) { return; }

        TriggerHandlerInterface instance = instantiate(handler.Class_Name__c);
        if (instance == null) { return; }

        Set<Id> addedIds = new Set<Id>();
        if (recordIds != null) {
            if (inProgress == null) {
                inProgress = new Set<Id>();
                inProgressIdsByHandler.put(handlerKey, inProgress);
            }
            for (Id recordId : recordIds) {
                if (inProgress.add(recordId)) { addedIds.add(recordId); }
            }
        }

        TriggerHandlerContext previousContext = currentContext;
        currentContext = context;
        try {
            instance.execute();
        } finally {
            currentContext = previousContext;
            if (inProgress != null) { inProgress.removeAll(addedIds); }
        }
    }

    /**
     * @param className The handler's class name.
     * @return a new instance, or null (with a warning in the debug log) if the class doesn't exist or isn't a handler.
     */
    private static TriggerHandlerInterface instantiate(String className) {
        Type classType;
        try {
            classType = Type.forName(className);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, className + ' does not compile and was skipped: ' + ex.getMessage());
            return null;
        }
        if (classType == null) {
            System.debug(LoggingLevel.WARN, 'Trigger_Handler__mdt references unknown Apex class: ' + className + '. Run TriggerHandlerManager.validateConfiguration() to find these.');
            return null;
        }
        Object instance = newInstanceOrNull(classType);
        if (instance == null) {
            System.debug(LoggingLevel.WARN, className + ' could not be instantiated: it needs a public constructor with no arguments.');
            return null;
        }
        if (!(instance instanceof TriggerHandlerInterface)) {
            System.debug(LoggingLevel.WARN, className + ' does not implement TriggerHandlerInterface.');
            return null;
        }
        return (TriggerHandlerInterface) instance;
    }

    /**
     * @param classType The class to instantiate.
     * @return a new instance, or null if the class has no public no-argument constructor.
     */
    private static Object newInstanceOrNull(Type classType) {
        try {
            return classType.newInstance();
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * @param objectName The SObject API name.
     * @return the active handlers for the object, in Order__c order.
     */
    private static List<Trigger_Handler__mdt> getHandlers(String objectName) {
        List<Trigger_Handler__mdt> matching = new List<Trigger_Handler__mdt>();
        for (Trigger_Handler__mdt handler : queryActiveHandlers(objectName)) {
            if (handler.Object__c != null && handler.Object__c.equalsIgnoreCase(objectName)) { matching.add(handler); }
        }
        return matching;
    }

    /**
     * Reads the configuration with Trigger_Handler__mdt.getAll() instead of SOQL: it doesn't count against the SOQL
     * limit, and it works for every user. A SOQL query on the type fails for users without access to it (common in
     * orgs that restrict custom metadata access), which would break every save those users make.
     * @param objectName The SObject API name, or null for every object. Filtering by object happens in getHandlers.
     * @return the active Trigger_Handler__mdt records, ordered by Order__c.
     */
    private static List<Trigger_Handler__mdt> queryActiveHandlers(String objectName) {
        List<Trigger_Handler__mdt> source = handlersOverride != null ? handlersOverride : Trigger_Handler__mdt.getAll().values();
        return activeInOrder(source);
    }

    /**
     * Keeps the active handlers and sorts them by Order__c.
     * @param handlers The handlers to filter and sort.
     * @return the active ones, ordered by Order__c (nulls last).
     */
    private static List<Trigger_Handler__mdt> activeInOrder(List<Trigger_Handler__mdt> handlers) {
        List<Trigger_Handler__mdt> sorted = new List<Trigger_Handler__mdt>();
        for (Trigger_Handler__mdt handler : handlers) {
            if (!handler.Is_Active__c) { continue; }
            Integer position = sorted.size();
            for (Integer i = 0; i < sorted.size(); i++) {
                if (handler.Order__c != null && (sorted[i].Order__c == null || handler.Order__c < sorted[i].Order__c)) {
                    position = i;
                    break;
                }
            }
            // Apex's add(index, element) rejects index == size(), so appending is its own case.
            if (position == sorted.size()) { sorted.add(handler); } else { sorted.add(position, handler); }
        }
        return sorted;
    }

    /**
     * @param handler The handler's configuration.
     * @return true if it's bypassed from code, or the running user has its Bypass_Permission__c.
     */
    private static Boolean isBypassed(Trigger_Handler__mdt handler) {
        if (isBypassed(handler.Class_Name__c)) { return true; }
        return String.isNotBlank(handler.Bypass_Permission__c) && FeatureManagement.checkPermission(handler.Bypass_Permission__c);
    }

    /**
     * @return true if the running user has the Bypass_All_Trigger_Handlers custom permission. Checked once per transaction.
     */
    private static Boolean isBypassAllForUser() {
        if (bypassAllForUser == null) {
            bypassAllForUser = FeatureManagement.checkPermission(BYPASS_ALL_PERMISSION);
        }
        return bypassAllForUser;
    }

    /**
     * @param handler The handler's configuration.
     * @param operationType The current trigger event.
     * @return true if the handler is configured for that event.
     */
    private static Boolean matchesEvent(Trigger_Handler__mdt handler, System.TriggerOperation operationType) {
        switch on operationType {
            when BEFORE_INSERT  { return handler.Before_Insert__c; }
            when BEFORE_UPDATE  { return handler.Before_Update__c; }
            when BEFORE_DELETE  { return handler.Before_Delete__c; }
            when AFTER_INSERT   { return handler.After_Insert__c; }
            when AFTER_UPDATE   { return handler.After_Update__c; }
            when AFTER_DELETE   { return handler.After_Delete__c; }
            when AFTER_UNDELETE { return handler.After_Undelete__c; }
        }
        return false;
    }

    /**
     * @param handler The handler's configuration.
     * @return true if at least one event checkbox is selected.
     */
    private static Boolean handlesAnyEvent(Trigger_Handler__mdt handler) {
        return handler.Before_Insert__c || handler.Before_Update__c || handler.Before_Delete__c
            || handler.After_Insert__c || handler.After_Update__c || handler.After_Delete__c || handler.After_Undelete__c;
    }

    /**
     * Resets the per-user bypass cache. Only tests need this, when they switch users with System.runAs.
     */
    @TestVisible
    private static void resetUserBypassCache() {
        bypassAllForUser = null;
    }
}
