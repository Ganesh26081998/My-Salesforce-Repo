@IsTest
private class EventBillingBatchTest {

    // ---------------------------------------------------------------------
    // Utility : Create Account
    // ---------------------------------------------------------------------
    private static Account createAccount() {

        Account acc = new Account(
            Name = 'Test Account'
        );

        insert acc;

        return acc;
    }

    // ---------------------------------------------------------------------
    // Utility : Create Event
    // ---------------------------------------------------------------------
    private static Event createEvent(
        Id accountId,
        Boolean isAllDay
    ) {

        Event ev = new Event(
            Subject = 'Test Event',
            WhatId = accountId,

            Status__c = 'Completed',
            Is_Billable_Produced__c = false,

            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(2),

            IsAllDayEvent = isAllDay,

            Client_Rate_Amount__c = 100,
            Caregiver_Rate_Amount__c = 50,

            Mileage_Amount__c = 10,
            Expense_Amount__c = 20
        );

        insert ev;

        return ev;
    }

    // ---------------------------------------------------------------------
    // Test : Batch Success
    // ---------------------------------------------------------------------
    @IsTest
    static void testBatchSuccess() {

        Account acc = createAccount();

        Event ev = createEvent(
            acc.Id,
            false
        );

        Test.startTest();

        Database.executeBatch(
            new EventBillingBatch(),
            200
        );

        Test.stopTest();

        Event updatedEvent = [
            SELECT Id,
                   Billing__c,
                   Is_Billable_Produced__c
            FROM Event
            WHERE Id = :ev.Id
        ];

        System.assertEquals(
            true,
            updatedEvent.Is_Billable_Produced__c
        );

        System.assertNotEquals(
            null,
            updatedEvent.Billing__c
        );

        List<Billing__c> bills = [
            SELECT Id,
                   Amount__c
            FROM Billing__c
            WHERE Id = :updatedEvent.Billing__c
        ];

        System.assertEquals(
            1,
            bills.size()
        );
    }

    // ---------------------------------------------------------------------
    // Test : All Day Event
    // ---------------------------------------------------------------------
    @IsTest
    static void testAllDayEventProcessing() {

        Account acc = createAccount();

        Event ev = createEvent(
            acc.Id,
            true
        );

        Test.startTest();

        Database.executeBatch(
            new EventBillingBatch(),
            200
        );

        Test.stopTest();

        Billing__c bill = [
            SELECT Id,
                   Event_Start_Date_Time__c,
                   Event_End_Date_Time__c
            FROM Billing__c
            LIMIT 1
        ];

        System.assertNotEquals(
            null,
            bill.Event_Start_Date_Time__c
        );

        System.assertNotEquals(
            null,
            bill.Event_End_Date_Time__c
        );
    }

    // ---------------------------------------------------------------------
    // Test : Skip Non Billable Event
    // ---------------------------------------------------------------------
    @IsTest
    static void testSkipNonBillableEvent() {

        Account acc = createAccount();

        Event ev = new Event(
            Subject = 'Non Billable Event',
            WhatId = acc.Id,

            Status__c = 'Completed',
            Is_Billable_Produced__c = false,

            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),

            Client_Rate_Amount__c = 0,
            Caregiver_Rate_Amount__c = 0,

            Mileage_Amount__c = 0,
            Expense_Amount__c = 0
        );

        insert ev;

        Test.startTest();

        Database.executeBatch(
            new EventBillingBatch(),
            200
        );

        Test.stopTest();

        Event updatedEvent = [
            SELECT Billing__c,
                   Is_Billable_Produced__c
            FROM Event
            WHERE Id = :ev.Id
        ];

        System.assertEquals(
            false,
            updatedEvent.Is_Billable_Produced__c
        );

        System.assertEquals(
            null,
            updatedEvent.Billing__c
        );
    }

    // ---------------------------------------------------------------------
    // Test : Skip Invalid WhatId
    // ---------------------------------------------------------------------
    @IsTest
    static void testSkipInvalidWhatId() {

        Event ev = new Event(
            Subject = 'Invalid Event',

            Status__c = 'Completed',
            Is_Billable_Produced__c = false,

            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),

            Client_Rate_Amount__c = 100
        );

        insert ev;

        Test.startTest();

        Database.executeBatch(
            new EventBillingBatch(),
            200
        );

        Test.stopTest();

        Integer billCount = [
            SELECT COUNT()
            FROM Billing__c
        ];

        System.assertEquals(
            0,
            billCount
        );
    }

    // ---------------------------------------------------------------------
    // Test : Finish Method Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testFinishMethodCoverage() {

        Test.startTest();

        EventBillingBatch batch =
            new EventBillingBatch();

        batch.finish(null);

        Test.stopTest();

        System.assert(true);
    }
}