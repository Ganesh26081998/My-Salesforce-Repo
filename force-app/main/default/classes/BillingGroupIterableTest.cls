@IsTest
private class BillingGroupIterableTest {

    @IsTest
    static void testBillingGroupIterator() {
        Date fromDate = Date.today();
        Date toDate = Date.today().addDays(3);

        // Create Test Account (Client)
        Account acc = new Account(
            Name = 'Test Client'
        );
        insert acc;

        // Create Billing Records
        List<Billing__c> billings = new List<Billing__c>();

        // Group 1 -> Same Client + Same Location
        billings.add(new Billing__c(
            Client__c = acc.Id,
           Is_Synced__c = false,
            Care_From_Date__c = fromDate,
            Care_To_Date__c = toDate,
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = fromDate,
            Invoice_Period_End_Date__c = toDate,
            Paid_Status__c = 'Paid',
            Amount__c = 100,
            Event_End_Date_Time__c = Datetime.newInstance(2026, 7, 8, 5, 0, 0),
            Event_Start_Date_Time__c = Datetime.newInstance(2026, 7, 9, 5, 0, 0)
        ));

        billings.add(new Billing__c(
            Client__c = acc.Id,
           Is_Synced__c = false,
            Care_From_Date__c = fromDate,
            Care_To_Date__c = toDate,
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = fromDate,
            Invoice_Period_End_Date__c = toDate,
            Paid_Status__c = 'Paid',
            Amount__c = 100,
            Event_End_Date_Time__c = Datetime.newInstance(2026, 7, 8, 5, 0, 0),
            Event_Start_Date_Time__c = Datetime.newInstance(2026, 7, 9, 5, 0, 0)
        ));

        // Group 2
        billings.add(new Billing__c(
            Client__c = acc.Id,
            Is_Synced__c = false,
            Care_From_Date__c = fromDate,
            Care_To_Date__c = toDate,
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = fromDate,
            Invoice_Period_End_Date__c = toDate,
            Paid_Status__c = 'Paid',
            Amount__c = 100,
            Event_End_Date_Time__c = Datetime.newInstance(2026, 7, 8, 5, 0, 0),
            Event_Start_Date_Time__c = Datetime.newInstance(2026, 7, 9, 5, 0, 0)
        ));

        insert billings;

        Test.startTest();

        BillingGroupIterable iterable = new BillingGroupIterable(billings);

        Iterator<List<Billing__c>> iterator = iterable.iterator();

        Integer groupCount = 0;

        while(iterator.hasNext()){

            List<Billing__c> newgroup = iterator.next();

            System.assertNotEquals(null, newgroup);
            System.assert(newgroup.size() > 0);

            groupCount++;

            if(groupCount == 1){
                
            }

            if(groupCount == 2){
                System.assertEquals(1, newgroup.size(),
                    'Second group should contain 1 record.');
            }
        }

        Test.stopTest();

        
    }

    @IsTest
    static void testIteratorNoSuchElementException() {
        Date fromDate = Date.today();
        Date toDate = Date.today().addDays(3);

        Account acc = new Account(
            Name = 'Client 2'
        );
        insert acc;

        Billing__c billing = new Billing__c(
            Client__c = acc.Id,
           	Is_Synced__c = false,
            Care_From_Date__c = fromDate,
            Care_To_Date__c = toDate,
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = fromDate,
            Invoice_Period_End_Date__c = toDate,
            Paid_Status__c = 'Paid',
            Amount__c = 100,
            Event_End_Date_Time__c = Datetime.newInstance(2026, 7, 8, 5, 0, 0),
            Event_Start_Date_Time__c = Datetime.newInstance(2026, 7, 9, 5, 0, 0)
        );

        insert billing;

        BillingGroupIterable iterable =
            new BillingGroupIterable(
                new List<Billing__c>{ billing }
            );

        Iterator<List<Billing__c>> iterator =
            iterable.iterator();

        // Consume the only group
        System.assert(iterator.hasNext());
        iterator.next();

        System.assertEquals(false, iterator.hasNext());

        Boolean exceptionThrown = false;

        try{
            iterator.next();
        }
        catch(NoSuchElementException ex){
            exceptionThrown = true;
            System.assert(
                ex.getMessage().contains('No more billing groups')
            );
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Expected NoSuchElementException to be thrown.'
        );
    }

    @IsTest
    static void testEmptyBillingList() {

        BillingGroupIterable iterable =
            new BillingGroupIterable(
                new List<Billing__c>()
            );

        Iterator<List<Billing__c>> iterator =
            iterable.iterator();

        System.assertEquals(
            false,
            iterator.hasNext()
        );
    }
}