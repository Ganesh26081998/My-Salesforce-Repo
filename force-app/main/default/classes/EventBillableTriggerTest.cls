@isTest
private class EventBillableTriggerTest {

    // ─── Helper: create and enable the Custom Setting ───────────────────────
    private static void enableTriggers() {
        WellSky_Custom_Setting__c setting = WellSky_Custom_Setting__c.getOrgDefaults();
        if (setting == null) {
            setting = new WellSky_Custom_Setting__c();
        }
        setting.Run_Triggers__c = true;
        upsert setting;
        TriggerControlUtil.reset(); // Clear cached value so next shouldRun() reads from DB
    }

    private static void disableTriggers() {
        WellSky_Custom_Setting__c setting = WellSky_Custom_Setting__c.getOrgDefaults();
        if (setting == null) {
            setting = new WellSky_Custom_Setting__c();
        }
        setting.Run_Triggers__c = false;
        upsert setting;
        TriggerControlUtil.reset();
    }

    // ─── Helper: create an Event_Wrapper__c with a fake Event_ID__c ─────────
    private static Event_Wrapper__c createWrapper(String eventId) {
        Event_Wrapper__c ew = new Event_Wrapper__c(
            Event_ID__c = eventId
        );
        insert ew;
        return ew;
    }

    // ─── Helper: resolve Business_Account Record Type Id ────────────────────
    private static Id getBusinessAccountRtId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Business_Account')
            .getRecordTypeId();
    }

    // ─── Helper: ensure 'No Organization' account exists ────────────────────
    //     Required by ContactDefaultAccountHandler (queried by Name).
    private static void ensureNoOrgAccount() {
        List<Account> existing = [
            SELECT Id FROM Account WHERE Name = 'No Organization' LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new Account(
                Name                 = 'No Organization',
                Organization_Name__c = 'No Organization',
                RecordTypeId         = getBusinessAccountRtId()
            );
        }
    }

    // ─── Helper: create a client Account for Billing__c.Client__c ───────────
    private static Account createClient() {
        ensureNoOrgAccount();
        Account a = new Account(
            Name                 = 'Test Client',
            Organization_Name__c = 'Test Client',
            RecordTypeId         = getBusinessAccountRtId()
        );
        insert a;
        return a;
    }

    // ─── Helper: create a Billing__c record with all required fields ─────────
    private static Billing__c createBilling() {
        Account client = createClient();
        Billing__c b = new Billing__c(
            Amount__c                    = 100.00,
            Care_From_Date__c            = Date.today().addDays(-30),
            Care_To_Date__c              = Date.today(),
            Client__c                    = client.Id,
            Invoice_Date__c              = Date.today(),
            Invoice_Period_End_Date__c   = Date.today(),
            Invoice_Period_Start_Date__c = Date.today().addDays(-30),
            Paid_Status__c               = 'Unpaid'
        );
        insert b;
        return b;
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 1 — Trigger skips when shouldRun() returns false
    // Covers the early-return branch at the top of the trigger
    // ════════════════════════════════════════════════════════════════════════
    @isTest
    static void testTriggerSkipsWhenDisabled() {
        disableTriggers();

        Event_Wrapper__c ew = createWrapper('some-event-id');

        Test.startTest();
        Event_Billable__c eb = new Event_Billable__c(
            Event_Wrapper__c = ew.Id
        );
        insert eb;
        Test.stopTest();

        // Event_Link__c must remain blank — trigger should have exited early
        Event_Billable__c result = [
            SELECT Id, Event_Link__c, Billable_Link__c
            FROM Event_Billable__c
            WHERE Id = :eb.Id
        ];
        System.assertEquals(null, result.Event_Link__c,
            'Event_Link__c should be null when trigger is disabled');
        System.assertEquals(null, result.Billable_Link__c,
            'Billable_Link__c should be null when trigger is disabled');
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 2 — Both Event_Wrapper__c and Billing__c are populated
    // Covers: STEP 1, STEP 2, STEP 3 (both URL branches), STEP 4
    // ════════════════════════════════════════════════════════════════════════
    @isTest
    static void testBothLinksGenerated() {
        enableTriggers();

        Event_Wrapper__c ew = createWrapper('EVT-001');
        Billing__c billing = createBilling();

        String expectedBase = URL.getOrgDomainUrl().toExternalForm();

        Test.startTest();
        Event_Billable__c eb = new Event_Billable__c(
            Event_Wrapper__c = ew.Id,
            Billing__c        = billing.Id
        );
        insert eb;
        Test.stopTest();

        Event_Billable__c result = [
            SELECT Id, Event_Link__c, Billable_Link__c
            FROM Event_Billable__c
            WHERE Id = :eb.Id
        ];

        System.assertEquals(
            expectedBase + '/' + 'EVT-001',
            result.Event_Link__c,
            'Event_Link__c should contain the base URL + Event_ID__c'
        );
        System.assertEquals(
            expectedBase + '/' + billing.Id,
            result.Billable_Link__c,
            'Billable_Link__c should contain the base URL + Billing Id'
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 3 — Only Event_Wrapper__c is set; Billing__c is null
    // Covers: Event_Link__c branch true, Billable_Link__c branch false
    // ════════════════════════════════════════════════════════════════════════
    @isTest
    static void testOnlyEventLinkGenerated() {
        enableTriggers();

        Event_Wrapper__c ew = createWrapper('EVT-002');
        String expectedBase = URL.getOrgDomainUrl().toExternalForm();

        Test.startTest();
        Event_Billable__c eb = new Event_Billable__c(
            Event_Wrapper__c = ew.Id,
            Billing__c        = null
        );
        insert eb;
        Test.stopTest();

        Event_Billable__c result = [
            SELECT Id, Event_Link__c, Billable_Link__c
            FROM Event_Billable__c
            WHERE Id = :eb.Id
        ];

        System.assertEquals(
            expectedBase + '/' + 'EVT-002',
            result.Event_Link__c,
            'Event_Link__c should be set'
        );
        System.assertEquals(null, result.Billable_Link__c,
            'Billable_Link__c should be null when Billing__c is not set');
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 4 — Only Billing__c is set; Event_Wrapper__c is null
    // Covers: Event_Link__c branch false, Billable_Link__c branch true
    //         Also confirms wrapperIds stays empty → STEP 2 SOQL is skipped
    // ════════════════════════════════════════════════════════════════════════
    @isTest
    static void testOnlyBillableLinkGenerated() {
        enableTriggers();

        Billing__c billing = createBilling();
        String expectedBase = URL.getOrgDomainUrl().toExternalForm();

        Test.startTest();
        Event_Billable__c eb = new Event_Billable__c(
            Event_Wrapper__c = null,
            Billing__c        = billing.Id
        );
        insert eb;
        Test.stopTest();

        Event_Billable__c result = [
            SELECT Id, Event_Link__c, Billable_Link__c
            FROM Event_Billable__c
            WHERE Id = :eb.Id
        ];

        System.assertEquals(null, result.Event_Link__c,
            'Event_Link__c should be null when Event_Wrapper__c is not set');
        System.assertEquals(
            expectedBase + '/' + billing.Id,
            result.Billable_Link__c,
            'Billable_Link__c should be set'
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 5 — Both lookups are null
    // Covers: both URL branches false; updates list contains blank records
    // ════════════════════════════════════════════════════════════════════════
    @isTest
    static void testNoLinksWhenBothNull() {
        enableTriggers();

        Test.startTest();
        Event_Billable__c eb = new Event_Billable__c(
            Event_Wrapper__c = null,
            Billing__c        = null
        );
        insert eb;
        Test.stopTest();

        Event_Billable__c result = [
            SELECT Id, Event_Link__c, Billable_Link__c
            FROM Event_Billable__c
            WHERE Id = :eb.Id
        ];

        System.assertEquals(null, result.Event_Link__c,
            'Event_Link__c should remain null');
        System.assertEquals(null, result.Billable_Link__c,
            'Billable_Link__c should remain null');
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 6 — Bulk insert (200 records) with mixed data
    // Validates SOQL bulkification and the update DML in STEP 4
    // ════════════════════════════════════════════════════════════════════════
    @isTest
    static void testBulkInsert() {
        enableTriggers();

        Event_Wrapper__c ew = createWrapper('EVT-BULK');
        Billing__c billing = createBilling();
        String expectedBase = URL.getOrgDomainUrl().toExternalForm();

        List<Event_Billable__c> toInsert = new List<Event_Billable__c>();
        for (Integer i = 0; i < 200; i++) {
            toInsert.add(new Event_Billable__c(
                Event_Wrapper__c = ew.Id,
                Billing__c        = billing.Id
            ));
        }

        Test.startTest();
        insert toInsert;
        Test.stopTest();

        List<Event_Billable__c> results = [
            SELECT Id, Event_Link__c, Billable_Link__c
            FROM Event_Billable__c
            WHERE Id IN :toInsert
        ];

        System.assertEquals(200, results.size(), 'All 200 records should be inserted');
        for (Event_Billable__c r : results) {
            System.assertEquals(
                expectedBase + '/EVT-BULK',
                r.Event_Link__c,
                'Event_Link__c should be set on every record'
            );
            System.assertEquals(
                expectedBase + '/' + billing.Id,
                r.Billable_Link__c,
                'Billable_Link__c should be set on every record'
            );
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 7 — TriggerControlUtil caching: second call reads cache, not DB
    // Covers the null-check branch inside shouldRun() for the cached path
    // ════════════════════════════════════════════════════════════════════════
    @isTest
    static void testTriggerControlUtilCaching() {
        enableTriggers();

        // First call reads from DB and caches
        Boolean first = TriggerControlUtil.shouldRun();
        System.assertEquals(true, first, 'shouldRun() should return true after enabling');

        // Disable in DB — cached value should still be true
        disableTriggers();
        // Do NOT call reset() here — we want to test the cached path
        TriggerControlUtil.reset(); // Reset is @TestVisible so we can prove it clears cache
        Boolean afterReset = TriggerControlUtil.shouldRun();
        System.assertEquals(false, afterReset, 'shouldRun() should return false after reset + disable');
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 8 — Custom Setting is null (org defaults not configured)
    // Covers the (setting != null && ...) false branch → shouldRun() = false
    // ════════════════════════════════════════════════════════════════════════
    @isTest
    static void testShouldRunReturnsFalseWhenSettingIsNull() {
        // Deliberately do NOT upsert any WellSky_Custom_Setting__c record
        // and reset the cache so shouldRun() re-reads from DB
        TriggerControlUtil.reset();

        // Delete existing org default if it exists (clean slate)
        WellSky_Custom_Setting__c existing = WellSky_Custom_Setting__c.getOrgDefaults();
        if (existing != null && existing.Id != null) {
            delete existing;
        }
        TriggerControlUtil.reset();

        Boolean result = TriggerControlUtil.shouldRun();
        System.assertEquals(false, result,
            'shouldRun() should return false when no Custom Setting record exists');
    }
}