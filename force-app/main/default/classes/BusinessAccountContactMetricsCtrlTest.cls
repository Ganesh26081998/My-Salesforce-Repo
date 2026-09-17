/*
----------------------------------------------------------------------------
Author        : Siva Naga Prasad
Class Name    : BusinessAccountContactMetricsCtrlTest
CreatedOn     : 14-05-2026
LastModifiedOn: 20-05-2026
LastModifiedBy: Siva Naga Prasad
Description   : Test class for BusinessAccountContactMetricsController 
                to validate contact metric aggregation, account metric 
                updates, business stage calculations, and exception handling.
----------------------------------------------------------------------------
*/

/*@isTest
private class BusinessAccountContactMetricsCtrlTest {

    @testSetup
    static void setupData() {
        // Create test account
        Account acc = new Account(
            Name = 'Test Business Account'
        );
        insert acc;

        // Create contacts with metrics
        List<Contact> contacts = new List<Contact>();

        contacts.add(new Contact(
            LastName = 'Contact One',
            AccountId = acc.Id,
            Lifetime_Revenue__c = 1000,
            Clients_Referred__c = 2,
            Prospects_Referred__c = 1
        ));

        contacts.add(new Contact(
            LastName = 'Contact Two',
            AccountId = acc.Id,
            Lifetime_Revenue__c = 500,
            Clients_Referred__c = 1,
            Prospects_Referred__c = 2
        ));

        insert contacts;
    }

    @isTest
    static void testGetContactMetricsSummary() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();

        BusinessAccountContactMetricsController.ContactMetricsSummary summary =
            BusinessAccountContactMetricsController.getContactMetricsSummary(acc.Id);

        Test.stopTest();

        System.assertEquals(1500, summary.lifetimeRevenue);
        System.assertEquals(3, summary.clientsReferred);
        System.assertEquals(3, summary.prospectsReferred);
    }

    @isTest
    static void testGetContactMetricsSummary_NullAccountId() {
        Test.startTest();

        try {
            BusinessAccountContactMetricsController.getContactMetricsSummary(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            //System.assert(e.getMessage().contains('Account Id is required'));
        }

        Test.stopTest();
    }

    @isTest
    static void testSaveMetricsToAccount_UpdatesFields() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();

        BusinessAccountContactMetricsController.saveMetricsToAccount(
            acc.Id,
            2,
            1,
            2500
        );

        Test.stopTest();

        Account updatedAcc = [
            SELECT
                Clients_Referred__c,
                Prospects_Referred__c,
                Lifetime_Revenue__c,
                Business_Stage__c,
                Business_Stage_Last_Updated_Date__c,
                Dormant_Notification_Sent__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals(2, updatedAcc.Clients_Referred__c);
        System.assertEquals(1, updatedAcc.Prospects_Referred__c);
        System.assertEquals(2500, updatedAcc.Lifetime_Revenue__c);

        // Since account is newly created and total referrals = 3
        System.assertEquals(
            'Referrals 2-3 within 30 days',
            updatedAcc.Business_Stage__c
        );

        //System.assertNotEquals(null,updatedAcc.Business_Stage_Last_Updated_Date__c);

        System.assertEquals(false,updatedAcc.Dormant_Notification_Sent__c);
    }

    @isTest
    static void testSaveMetricsToAccount_4to8Stage() {
        Account acc = new Account(Name = '90 Day Account');
        insert acc;

        Test.startTest();

        BusinessAccountContactMetricsController.saveMetricsToAccount(
            acc.Id,
            4,
            2,
            4000
        );

        Test.stopTest();

        Account updatedAcc = [
            SELECT Business_Stage__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals(
            'Referrals 4-8 within 90 days',
            updatedAcc.Business_Stage__c
        );
    }

    @isTest
    static void testSaveMetricsToAccount_NullValues() {
        Account acc = new Account(Name = 'Null Values Account');
        insert acc;

        Test.startTest();

        BusinessAccountContactMetricsController.saveMetricsToAccount(
            acc.Id,
            null,
            null,
            null
        );

        Test.stopTest();

        Account updatedAcc = [
            SELECT
                Clients_Referred__c,
                Prospects_Referred__c,
                Lifetime_Revenue__c,
                Business_Stage__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals(0, updatedAcc.Clients_Referred__c);
        System.assertEquals(0, updatedAcc.Prospects_Referred__c);
        System.assertEquals(0, updatedAcc.Lifetime_Revenue__c);
        System.assertEquals(null, updatedAcc.Business_Stage__c);
    }

    @isTest
    static void testSaveMetricsToAccount_NullAccountId() {

        Test.startTest();

        try {
            BusinessAccountContactMetricsController.saveMetricsToAccount(
                null,
                1,
                1,
                100
            );

            System.assert(false, 'Expected AuraHandledException');

        } catch (AuraHandledException e) {

        }

        Test.stopTest();
    }
}*/

/*
----------------------------------------------------------------------------
Author        : Siva Naga Prasad
Class Name    : BusinessAccountContactMetricsCtrlTest
CreatedOn     : 14-05-2026
LastModifiedOn: 03-07-2026
LastModifiedBy: Siva Naga Prasad
Description   : Test class for BusinessAccountContactMetricsController 
                to validate contact metric aggregation and batch execution.
----------------------------------------------------------------------------
*/
@isTest
private class BusinessAccountContactMetricsCtrlTest {

    @testSetup
    static void setupData() {
        // Create test account
        Account acc = new Account(
            Name = 'Test Business Account'
            
        );
        insert acc;

        // Create contacts with metrics
        List<Contact> contacts = new List<Contact>();

        contacts.add(new Contact(
            LastName = 'Contact One',
            AccountId = acc.Id,
            Lifetime_Revenue__c = 1000,
            Clients_Referred__c = 2,
            Prospects_Referred__c = 1
        ));

        contacts.add(new Contact(
            LastName = 'Contact Two',
            AccountId = acc.Id,
            Lifetime_Revenue__c = 500,
            Clients_Referred__c = 1,
            Prospects_Referred__c = 2
        ));

        insert contacts;
    }

    @isTest
    static void testGetContactMetricsSummary() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        BusinessAccountContactMetricsController.ContactMetricsSummary summary =
            BusinessAccountContactMetricsController.getContactMetricsSummary(acc.Id);
        Test.stopTest();

        System.assertEquals(1500, summary.lifetimeRevenue);
        System.assertEquals(3, summary.clientsReferred);
        System.assertEquals(3, summary.prospectsReferred);
    }

    @isTest
    static void testGetContactMetricsSummary_NullAccountId() {
        Test.startTest();
        try {
            BusinessAccountContactMetricsController.getContactMetricsSummary(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            // Success path for catch block
        }
        Test.stopTest();
    }

    @isTest
    static void testRunAccountBatch_StartsJob() {
        Test.startTest();
        // Call the new controller method that spins up the async batch process
        BusinessAccountContactMetricsController.runAccountBatch();
        Test.stopTest();
        
        // Query to check if the batch job was put into the system queue successfully
        AsyncApexJob[] jobs = [SELECT Id, JobType, Status FROM AsyncApexJob WHERE JobType = 'BatchApex'];
        System.assert(jobs.size() > 0, 'The batch job was not successfully submitted to the queue.');
    }
}