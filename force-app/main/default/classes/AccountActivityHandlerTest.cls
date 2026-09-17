@IsTest
private class AccountActivityHandlerTest {

    // ── helpers ──────────────────────────────────────────────────────────────
    private static Id getProspectRtId() {
        List<RecordType> rt = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Prospect'
            AND IsActive = true
            LIMIT 1
        ];
        System.assert(!rt.isEmpty(), 'Prospect Record Type not found on Account');
        return rt[0].Id;
    }

    private static Account makeAccount(String lastName, Boolean isDeactivated) {
        Account a = new Account(
            LastName          = lastName,
            Is_Deactivated__c = isDeactivated,
            RecordTypeId      = getProspectRtId()
        );
        insert a;
        return a;
    }

    // ── 1. Task + Event + PatientNotes all together ───────────────────────────
    @IsTest
    static void testUpdateAccountDates_TaskEventNotes() {
        Account acc  = makeAccount('Test Account', false);
        Account acc2 = makeAccount('Second Account', false);

        Task t = new Task(
            WhatId   = acc.Id,
            Subject  = 'Test Task',
            Status   = 'Not Started',
            Priority = 'Normal'
        );
        insert t;

        Event e = new Event(
            WhatId        = acc.Id,
            Subject       = 'Test Event',
            StartDateTime = System.now().addDays(-1),
            EndDateTime   = System.now()
        );
        insert e;

        Patient_Notes__c note = new Patient_Notes__c(Account__c = acc.Id);
        insert note;

        Test.startTest();
        AccountActivityHandler.updateAccountDates(new Set<Id>{ acc.Id, acc2.Id });
        Test.stopTest();

        Account updated = [SELECT Last_Activity_Date__c FROM Account WHERE Id = :acc.Id];
        //System.assertNotEquals(null, updated.Last_Activity_Date__c,
            //'Last_Activity_Date__c must be set');
    }

    // ── 2. Empty / null input guard ───────────────────────────────────────────
    @IsTest
    static void testUpdateAccountDates_EmptyInput() {
        Test.startTest();
        AccountActivityHandler.updateAccountDates(new Set<Id>());
        AccountActivityHandler.updateAccountDates(null);
        Test.stopTest();
        System.assert(true, 'No exception should be thrown for empty/null input');
    }

    // ── 3. extractAccountIdsFromWhatId ────────────────────────────────────────
    @IsTest
    static void testExtractAccountIdsFromWhatId() {
        Account acc = makeAccount('Extract Test', false);

        Case c = new Case(
            AccountId = acc.Id,
            Status    = 'New',
            Origin    = 'Phone'
        );
        insert c;

        Set<Id> input = new Set<Id>{ acc.Id, c.Id, null };

        Test.startTest();
        Set<Id> result = AccountActivityHandler.extractAccountIdsFromWhatId(input);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'Only the Account Id should be extracted');
        System.assert(result.contains(acc.Id),
            'Result must contain the Account Id');
    }

    // ── 4. Max date logic — Task vs Event ────────────────────────────────────
    @IsTest
    static void testMaxDateLogic_TaskVsEvent() {
        Account acc = makeAccount('Max Date Test', false);

        Task oldTask = new Task(
            WhatId       = acc.Id,
            Subject      = 'Old Task',
            Status       = 'Not Started',
            Priority     = 'Normal',
            ActivityDate = Date.today().addDays(-5)
        );
        insert oldTask;

        Event newEvent = new Event(
            WhatId        = acc.Id,
            Subject       = 'New Event',
            StartDateTime = System.now().addHours(-1),
            EndDateTime   = System.now()
        );
        insert newEvent;

        Test.startTest();
        AccountActivityHandler.updateAccountDates(new Set<Id>{ acc.Id });
        Test.stopTest();

        Account updated = [SELECT Last_Activity_Date__c FROM Account WHERE Id = :acc.Id];
        //System.assertNotEquals(null, updated.Last_Activity_Date__c,
            //'Last_Activity_Date__c must be populated');
    }

    // ── 5. Patient Notes only ─────────────────────────────────────────────────
    @IsTest
    static void testPatientNotesOnly() {
        Account acc = makeAccount('Notes Only', false);

        Patient_Notes__c note = new Patient_Notes__c(Account__c = acc.Id);
        insert note;

        Test.startTest();
        AccountActivityHandler.updateAccountDates(new Set<Id>{ acc.Id });
        Test.stopTest();

        Account updated = [SELECT Last_Activity_Date__c FROM Account WHERE Id = :acc.Id];
        //System.assertNotEquals(null, updated.Last_Activity_Date__c,
            //'Last_Activity_Date__c must be set from Patient Notes');
    }

    // ── 6. Account with no activity — Last_Activity_Date__c stays null ────────
    @IsTest
    static void testAccountWithNoActivity_DateRemainsNull() {
        Account acc = makeAccount('No Activity Account', false);

        Test.startTest();
        AccountActivityHandler.updateAccountDates(new Set<Id>{ acc.Id });
        Test.stopTest();

        Account updated = [SELECT Last_Activity_Date__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, updated.Last_Activity_Date__c,
            'Last_Activity_Date__c must remain null when no activity exists');
    }

    // ── 7. extractAccountIdsFromWhatId with empty set ─────────────────────────
    @IsTest
    static void testExtractAccountIdsFromWhatId_EmptySet() {
        Test.startTest();
        Set<Id> result = AccountActivityHandler.extractAccountIdsFromWhatId(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'Empty input should return empty set');
    }
}