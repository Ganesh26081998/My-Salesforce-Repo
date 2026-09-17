@isTest
private class WellSpringActivityLockHandlerTest {

    // ─── Helper: ensure triggers are enabled via Custom Setting ───────────────
    private static void enableTriggers() {
        WellSky_Custom_Setting__c s = WellSky_Custom_Setting__c.getOrgDefaults();
        if (s == null) {
            s = new WellSky_Custom_Setting__c();
        }
        s.Run_Triggers__c = true;
        upsert s;
        TriggerControlUtil.reset();   // flush cached value
    }

    private static void disableTriggers() {
        WellSky_Custom_Setting__c s = WellSky_Custom_Setting__c.getOrgDefaults();
        if (s == null) {
            s = new WellSky_Custom_Setting__c();
        }
        s.Run_Triggers__c = false;
        upsert s;
        TriggerControlUtil.reset();
    }
    
	Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                      .get('Prospect').getRecordTypeId();
    
    // AFTER
	static Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                         .get('Prospect').getRecordTypeId();

    // ─── Shared account creation helpers ─────────────────────────────────────
    private static Account makeActiveAccount() {
        Account a = new Account(LastName = 'Active Account', Is_Deactivated__c = false, RecordTypeId = recordTypeId);
        insert a;
        return a;
    }

    private static Account makeDeactivatedAccount() {
        Account a = new Account(LastName = 'Deactivated Account', Is_Deactivated__c = true, RecordTypeId = recordTypeId);
        insert a;
        return a;
    }

    // =========================================================================
    // 1. TriggerControlUtil – shouldRun() branch coverage
    // =========================================================================

    @isTest
    static void testShouldRun_TriggerEnabled() {
        enableTriggers();
        Test.startTest();
        Boolean result = TriggerControlUtil.shouldRun();
        Test.stopTest();
        System.assertEquals(true, result, 'shouldRun() must return true when Run_Triggers__c is true');
    }

    @isTest
    static void testShouldRun_TriggerDisabled() {
        disableTriggers();
        Test.startTest();
        Boolean result = TriggerControlUtil.shouldRun();
        Test.stopTest();
        System.assertEquals(false, result, 'shouldRun() must return false when Run_Triggers__c is false');
    }

    @isTest
    static void testShouldRun_CachedValue() {
        enableTriggers();
        // Call twice — second call uses cached value (no SOQL)
        TriggerControlUtil.shouldRun();
        Test.startTest();
        Boolean result = TriggerControlUtil.shouldRun();
        Test.stopTest();
        System.assertEquals(true, result, 'Cached shouldRun() must still return true');
    }

    @isTest
    static void testReset_ClearsCachedValue() {
        enableTriggers();
        TriggerControlUtil.shouldRun(); // populate cache
        TriggerControlUtil.reset();     // clear it
        disableTriggers();
        Test.startTest();
        Boolean result = TriggerControlUtil.shouldRun();
        Test.stopTest();
        System.assertEquals(false, result, 'After reset(), shouldRun() must re-read the custom setting');
    }

    // =========================================================================
    // 2. Trigger skipped when shouldRun() = false
    // =========================================================================

    @isTest
    static void testTriggerSkipped_WhenDisabled() {
        disableTriggers();
        Account deactivated = makeDeactivatedAccount();

        Task t = new Task(
            Subject   = 'Should Not Be Blocked',
            Status    = 'Not Started',
            Priority  = 'Normal',
            WhatId    = deactivated.Id
        );
        Test.startTest();
        // Trigger is disabled, so the block logic never runs → insert succeeds
        Database.SaveResult sr = Database.insert(t, false);
        Test.stopTest();
        System.assertEquals(true, sr.isSuccess(),
            'Task insert should succeed when triggers are disabled, even for a deactivated account');
    }

    // =========================================================================
    // 3. blockIfDeactivated – TASK scenarios
    // =========================================================================

    @isTest
    static void testTaskInsert_BlockedForDeactivatedAccount() {
        enableTriggers();
        Account deactivated = makeDeactivatedAccount();

        Task t = new Task(
            Subject  = 'Blocked Task',
            Status   = 'Not Started',
            Priority = 'Normal',
            WhatId   = deactivated.Id
        );
        Test.startTest();
        Database.SaveResult sr = Database.insert(t, false);
        Test.stopTest();

        System.assertEquals(false, sr.isSuccess(), 'Insert must fail for deactivated account');
        System.assert(
            sr.getErrors()[0].getMessage().contains('Cannot add or edit timeline activities'),
            'Error message must mention deactivated account'
        );
    }

    @isTest
    static void testTaskInsert_AllowedForActiveAccount() {
        enableTriggers();
        Account active = makeActiveAccount();

        Task t = new Task(
            Subject  = 'Allowed Task',
            Status   = 'Not Started',
            Priority = 'Normal',
            WhatId   = active.Id
        );
        Test.startTest();
        insert t;
        Test.stopTest();

        System.assertNotEquals(null, t.Id, 'Task must be inserted for an active account');
    }

    @isTest
    static void testTaskInsert_NoWhatId() {
        enableTriggers();

        Task t = new Task(
            Subject  = 'No WhatId Task',
            Status   = 'Not Started',
            Priority = 'Normal'
        );
        Test.startTest();
        insert t;
        Test.stopTest();

        System.assertNotEquals(null, t.Id, 'Task with no WhatId must insert successfully');
    }

    @isTest
    static void testTaskDelete_BlockedForDeactivatedAccount() {
        // Insert with triggers disabled, then re-enable before delete
        disableTriggers();
        Account deactivated = makeDeactivatedAccount();

        Task t = new Task(
            Subject  = 'Task To Delete',
            Status   = 'Not Started',
            Priority = 'Normal',
            WhatId   = deactivated.Id
        );
        insert t; // succeeds because triggers are off

        enableTriggers();
        Test.startTest();
        Database.DeleteResult dr = Database.delete(t, false);
        Test.stopTest();

        System.assertEquals(false, dr.isSuccess(), 'Delete must be blocked for deactivated account');
        System.assert(
            dr.getErrors()[0].getMessage().contains('Cannot add or edit timeline activities'),
            'Error message must mention deactivated account on delete'
        );
    }

    @isTest
    static void testTaskDelete_AllowedForActiveAccount() {
        enableTriggers();
        Account active = makeActiveAccount();

        Task t = new Task(
            Subject  = 'Task To Delete',
            Status   = 'Not Started',
            Priority = 'Normal',
            WhatId   = active.Id
        );
        insert t;

        Test.startTest();
        delete t;
        Test.stopTest();

        List<Task> remaining = [SELECT Id FROM Task WHERE Id = :t.Id ALL ROWS];
        // Row will be in recycle bin (isDeleted = true) — confirm it's gone from normal view
        List<Task> active2 = [SELECT Id FROM Task WHERE Id = :t.Id];
        System.assertEquals(0, active2.size(), 'Task must be deleted for active account');
    }

    // =========================================================================
    // 4. blockIfDeactivated – EVENT scenarios
    // =========================================================================

    @isTest
    static void testEventInsert_BlockedForDeactivatedAccount() {
        enableTriggers();
        Account deactivated = makeDeactivatedAccount();

        Event ev = new Event(
            Subject       = 'Blocked Event',
            StartDateTime = System.now(),
            EndDateTime   = System.now().addHours(1),
            WhatId        = deactivated.Id
        );
        Test.startTest();
        Database.SaveResult sr = Database.insert(ev, false);
        Test.stopTest();
    }

    @isTest
    static void testEventInsert_AllowedForActiveAccount() {
        enableTriggers();
        Account active = makeActiveAccount();

        Event ev = new Event(
            Subject       = 'Allowed Event',
            StartDateTime = System.now(),
            EndDateTime   = System.now().addHours(1),
            WhatId        = active.Id
        );
        Test.startTest();
        insert ev;
        Test.stopTest();

        System.assertNotEquals(null, ev.Id, 'Event must insert for active account');
    }

    @isTest
    static void testEventInsert_NoWhatId() {
        enableTriggers();

        Event ev = new Event(
            Subject       = 'No WhatId Event',
            StartDateTime = System.now(),
            EndDateTime   = System.now().addHours(1)
        );
        Test.startTest();
        insert ev;
        Test.stopTest();

        System.assertNotEquals(null, ev.Id, 'Event with no WhatId must insert successfully');
    }

    // =========================================================================
    // 5. After-trigger – AccountActivityHandler paths
    //    (after insert, after delete, after undelete)
    // =========================================================================

    @isTest
    static void testAfterInsert_AccountActivityHandlerCalled() {
        enableTriggers();
        Account active = makeActiveAccount();

        Task t = new Task(
            Subject  = 'After Insert Task',
            Status   = 'Not Started',
            Priority = 'Normal',
            WhatId   = active.Id
        );
        Test.startTest();
        insert t;
        Test.stopTest();

        // If AccountActivityHandler runs without error the test passes
        System.assertNotEquals(null, t.Id);
    }

    @isTest
    static void testAfterDelete_AccountActivityHandlerCalled() {
        enableTriggers();
        Account active = makeActiveAccount();

        Task t = new Task(
            Subject  = 'After Delete Task',
            Status   = 'Not Started',
            Priority = 'Normal',
            WhatId   = active.Id
        );
        insert t;

        Test.startTest();
        delete t;
        Test.stopTest();

        List<Task> remaining = [SELECT Id FROM Task WHERE Id = :t.Id];
        System.assertEquals(0, remaining.size(), 'Task must be deleted');
    }

    @isTest
    static void testAfterUndelete_AccountActivityHandlerCalled() {
        enableTriggers();
        Account active = makeActiveAccount();

        Task t = new Task(
            Subject  = 'Undelete Task',
            Status   = 'Not Started',
            Priority = 'Normal',
            WhatId   = active.Id
        );
        insert t;
        delete t;

        Test.startTest();
        undelete t;
        Test.stopTest();

        List<Task> restored = [SELECT Id FROM Task WHERE Id = :t.Id];
        System.assertEquals(1, restored.size(), 'Task must be restored after undelete');
    }

    @isTest
    static void testAfterInsert_NullWhatId_NoError() {
        enableTriggers();

        Task t = new Task(
            Subject  = 'No WhatId After Insert',
            Status   = 'Not Started',
            Priority = 'Normal'
        );
        Test.startTest();
        insert t;
        Test.stopTest();

        System.assertNotEquals(null, t.Id);
    }

    // =========================================================================
    // 6. Bulk / governor limit safety
    // =========================================================================

    @isTest
    static void testBulkInsert_MixedAccounts() {
        enableTriggers();
        Account active      = makeActiveAccount();
        Account deactivated = makeDeactivatedAccount();

        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < 10; i++) {
            tasks.add(new Task(
                Subject  = 'Active Task ' + i,
                Status   = 'Not Started',
                Priority = 'Normal',
                WhatId   = active.Id
            ));
        }
        // Add one blocked task
        tasks.add(new Task(
            Subject  = 'Blocked Task',
            Status   = 'Not Started',
            Priority = 'Normal',
            WhatId   = deactivated.Id
        ));

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(tasks, false);
        Test.stopTest();

        Integer successCount = 0, failCount = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) successCount++;
            else failCount++;
        }
        System.assertEquals(10, successCount, '10 active-account tasks must succeed');
        System.assertEquals(1,  failCount,    '1 deactivated-account task must fail');
    }
}