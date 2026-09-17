@isTest
private class BillableListViewControllerTest {

    @testSetup
    static void createTestData() {

        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        List<Billing__c> billings = new List<Billing__c>();

        // Record that should be returned
        billings.add(new Billing__c(
            Client__c = acc.Id,
            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today().addDays(7),
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today().addDays(7),
            Paid_Status__c = 'Unpaid',
            QB_Sync_Status__c = 'Failed',
            Amount__c=1000
        ));

        // Record that should NOT be returned
        billings.add(new Billing__c(
            Client__c = acc.Id,
            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today().addDays(7),
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today().addDays(7),
            Paid_Status__c = 'Unpaid',
            QB_Sync_Status__c = 'Synced',
            Amount__c=1000
        ));

        insert billings;
    }

    @isTest
    static void testGetBillables() {

        Test.startTest();

        List<Billing__c> results =
            BillableListViewController.getBillables();

        Test.stopTest();

        
        for(Billing__c bill : results) {

            System.assertNotEquals(
                'Synced',
                bill.QB_Sync_Status__c,
                'Synced records should not be returned'
            );

            System.assertNotEquals(
                null,
                bill.Id
            );
        }
    }
    
    @isTest
static void testOfficeHoursClientExcluded() {

    // Get Prospect Record Type
    RecordType prospectRT = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account'
        AND DeveloperName = 'Prospect'
        LIMIT 1
    ];

    // This account should be excluded
   Account officeHoursAcc = new Account(
    RecordTypeId = prospectRT.Id,
    FirstName = 'WellSpring Office Hours',
    LastName = 'Milwaukee'
);
    insert officeHoursAcc;

    // This account should be included
   Account normalAcc = new Account(
    RecordTypeId = prospectRT.Id,
    FirstName = 'John',
    LastName = 'Smith'
);
    insert normalAcc;

    insert new List<Billing__c>{

        new Billing__c(
            Client__c = officeHoursAcc.Id,
            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today().addDays(1),
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today().addDays(1),
            Paid_Status__c = 'Unpaid',
            QB_Sync_Status__c = 'Pending',
            Amount__c = 100
        ),

        new Billing__c(
            Client__c = normalAcc.Id,
            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today().addDays(1),
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today().addDays(1),
            Paid_Status__c = 'Unpaid',
            QB_Sync_Status__c = 'Pending',
            Amount__c = 200
        )
    };

    Test.startTest();

    List<Billing__c> results =
        BillableListViewController.getBillables();

    Test.stopTest();

    System.assertEquals(1, results.size());

    System.assertEquals(
        'John Smith',
        results[0].Client__r.Name
    );

    System.assert(
        !results[0].Client__r.Name.startsWith('WellSpring Office Hours')
    );
}
}