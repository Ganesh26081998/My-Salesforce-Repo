@IsTest
private class BillingDataCorrectionBatchTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'Test Client'
        );
        insert acc;

        Billing__c normalBilling = new Billing__c(
            Client__c = acc.Id,
            Amount__c = 0,
            Care_From_Date__c = Date.newInstance(2026, 2, 16),
            Care_To_Date__c = Date.newInstance(2026, 2, 16),
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = Date.newInstance(2026, 2, 1),
            Invoice_Period_End_Date__c = Date.newInstance(2026, 2, 28),
            Paid_Status__c = 'Paid',
            Is_Historic_Data__c = false
        );

        Billing__c allDayBilling = new Billing__c(
            Client__c = acc.Id,
            Invoice_Date__c = Date.today(),
            Amount__c = 0,
            Care_From_Date__c = Date.newInstance(2026, 2, 16),
            Care_To_Date__c = Date.newInstance(2026, 2, 16),
            Invoice_Period_Start_Date__c = Date.newInstance(2026, 2, 1),
            Invoice_Period_End_Date__c = Date.newInstance(2026, 2, 28),
            Paid_Status__c = 'Paid',
            Is_Historic_Data__c = false
        );

        insert new List<Billing__c>{ normalBilling, allDayBilling };

        // The batch excludes Billings created THIS_MONTH, so push CreatedDate
        // back to make these records eligible for the batch query.
        Test.setCreatedDate(normalBilling.Id, Datetime.now().addMonths(-2));
        Test.setCreatedDate(allDayBilling.Id, Datetime.now().addMonths(-2));

        Datetime normalStart = Datetime.newInstance(
            Date.today().addDays(-2),
            Time.newInstance(9, 0, 0, 0)
        );
        Datetime normalEnd = normalStart.addMinutes(150);

        Event normalEvent = new Event(
            Subject = 'Migrated Shift - Normal Event',
            WhatId = acc.Id,
            StartDateTime = normalStart,
            EndDateTime = normalEnd,
            Is_Billable_Produced__c = true,
            Billing__c = normalBilling.Id,
            Client_Rate_Amount__c = 100,
            Caregiver_Rate_Amount__c = 40,
            Client_Rate__c = 'Hourly'
        );

        Date allDayDate = Date.today().addDays(-1);
        Event allDayEvent = new Event(
            Subject = 'Migrated Shift - All Day Event',
            WhatId = acc.Id,
            ActivityDate = allDayDate,
            IsAllDayEvent = true,
            Is_Billable_Produced__c = true,
            Billing__c = allDayBilling.Id,
            Client_Rate_Amount__c = 50,
            Caregiver_Rate_Amount__c = 20,
            Client_Rate__c = 'Hourly'
        );

        insert new List<Event>{ normalEvent, allDayEvent };

        List<Billing_Line_Item__c> lineItems = new List<Billing_Line_Item__c>();
        lineItems.add(
            new Billing_Line_Item__c(
                Invoice__c = normalBilling.Id,
                Type__c = 'Client Billable',
                Amount__c = 100,
                Quantity__c = 1,
                Rate__c = 100,
                Service_Date__c = Date.today()
            )
        );
        lineItems.add(
            new Billing_Line_Item__c(
                Invoice__c = normalBilling.Id,
                Type__c = 'Caregiver Billable',
                Amount__c = 40,
                Quantity__c = 1,
                Rate__c = 40,
                Service_Date__c = Date.today()
            )
        );
        lineItems.add(
            new Billing_Line_Item__c(
                Invoice__c = normalBilling.Id,
                Type__c = 'Mileage',
                Amount__c = 25,
                Quantity__c = 1,
                Rate__c = 25,
                Service_Date__c = Date.today()
            )
        );
        lineItems.add(
            new Billing_Line_Item__c(
                Invoice__c = allDayBilling.Id,
                Type__c = 'Client Billable',
                Amount__c = 50,
                Quantity__c = 1,
                Rate__c = 50,
                Service_Date__c = Date.today()
            )
        );
        lineItems.add(
            new Billing_Line_Item__c(
                Invoice__c = allDayBilling.Id,
                Type__c = 'Caregiver Billable',
                Amount__c = 20,
                Quantity__c = 1,
                Rate__c = 20,
                Service_Date__c = Date.today()
            )
        );
        insert lineItems;
    }

    @IsTest
    static void testBillingDataCorrectionBatch() {
        Test.startTest();
        Database.executeBatch(
            new BillingDataCorrectionBatch('Migrated Shift'),
            200
        );
        Test.stopTest();

        Map<String, Event> eventsBySubject = new Map<String, Event>();
        for (Event ev : [
            SELECT Id, Subject, Billing__c
            FROM Event
            WHERE Subject LIKE 'Migrated Shift%'
        ]) {
            eventsBySubject.put(ev.Subject, ev);
        }

        Id normalBillingId = eventsBySubject.get(
            'Migrated Shift - Normal Event'
        ).Billing__c;
        Id allDayBillingId = eventsBySubject.get(
            'Migrated Shift - All Day Event'
        ).Billing__c;

        Map<String, Billing_Line_Item__c> normalItems = new Map<String, Billing_Line_Item__c>();
        for (Billing_Line_Item__c bli : [
            SELECT Type__c, Quantity__c, Rate__c, Amount__c
            FROM Billing_Line_Item__c
            WHERE Invoice__c = :normalBillingId
        ]) {
            normalItems.put(bli.Type__c, bli);
        }

        // Event duration is 150 minutes = 2.5 hours
        Billing_Line_Item__c normalClient = normalItems.get('Client Billable');
        System.assertEquals(2.50, normalClient.Quantity__c);
        System.assertEquals(100, normalClient.Rate__c);
        System.assertEquals(250.00, normalClient.Amount__c);

        Billing_Line_Item__c normalCaregiver = normalItems.get('Caregiver Billable');
        System.assertEquals(2.50, normalCaregiver.Quantity__c);
        System.assertEquals(40, normalCaregiver.Rate__c);
        System.assertEquals(100.00, normalCaregiver.Amount__c);

        Map<String, Billing_Line_Item__c> allDayItems = new Map<String, Billing_Line_Item__c>();
        for (Billing_Line_Item__c bli : [
            SELECT Type__c, Quantity__c, Rate__c, Amount__c
            FROM Billing_Line_Item__c
            WHERE Invoice__c = :allDayBillingId
        ]) {
            allDayItems.put(bli.Type__c, bli);
        }

        Billing_Line_Item__c allDayClient = allDayItems.get('Client Billable');
        //System.assertEquals(1.00, allDayClient.Quantity__c);
        System.assertEquals(50, allDayClient.Rate__c);
        System.assertEquals(1200, allDayClient.Amount__c);

        Billing_Line_Item__c allDayCaregiver = allDayItems.get('Caregiver Billable');
        System.assertEquals(24, allDayCaregiver.Quantity__c);
        System.assertEquals(20, allDayCaregiver.Rate__c);
        System.assertEquals(480, allDayCaregiver.Amount__c);

        Map<Id, Billing__c> billings = new Map<Id, Billing__c>([
            SELECT Id, Amount__c
            FROM Billing__c
            WHERE Id IN :new Set<Id>{ normalBillingId, allDayBillingId }
        ]);
        System.assertEquals(275, billings.get(normalBillingId).Amount__c);
        System.assertEquals(1200, billings.get(allDayBillingId).Amount__c);
    }
}