@isTest
private class BusinessAccountMetricsBatchTest {

    @isTest
    static void testAccountMetricsCalculation() {
        // 1. Setup Test Data: Create a Business Account
        Account testAcc = new Account(
            Name = 'Test Business Partner Corp'
            
        );
        insert testAcc;

        // 2. Setup Test Data: Create related Contacts with metrics populated
        List<Contact> testContacts = new List<Contact>{
            new Contact(
                FirstName = 'Alice',
                LastName = 'Smith',
                AccountId = testAcc.Id,
                Clients_Referred__c = 2,
                Prospects_Referred__c = 1,
                Lifetime_Revenue__c = 1500.00
            ),
            new Contact(
                FirstName = 'Bob',
                LastName = 'Jones',
                AccountId = testAcc.Id,
                Clients_Referred__c = 1,
                Prospects_Referred__c = 2,
                Lifetime_Revenue__c = 2500.00
            )
        };
        insert testContacts;

        // 3. Execute the Batch Job
        Test.startTest();
        BusinessAccountMetricsBatch batchJob = new BusinessAccountMetricsBatch();
        Database.executeBatch(batchJob, 200);
        Test.stopTest(); // Forces asynchronous batch jobs to complete before moving forward

        // 4. Verify Results from Database Backend
        Account updatedAcc = [
            SELECT Clients_Referred__c, Prospects_Referred__c, Lifetime_Revenue__c, Business_Stage__c 
            FROM Account 
            WHERE Id = :testAcc.Id
        ];

        // Assert that the sums match the Contact data perfectly
        System.assertEquals(3, updatedAcc.Clients_Referred__c, 'Clients referred calculation mismatch');
        System.assertEquals(3, updatedAcc.Prospects_Referred__c, 'Prospects referred calculation mismatch');
        System.assertEquals(4000.00, updatedAcc.Lifetime_Revenue__c, 'Lifetime Revenue calculation mismatch');
        
        // Total referrals = 3 + 3 = 6. 
        // Account age is 0 days (<= 90 days), so it should match the 4-8 referral band.
        System.assertEquals('Referrals 4-8 within 90 days', updatedAcc.Business_Stage__c, 'Business stage evaluation rule failed');
    }

    @isTest
    static void testAccountWithNoContacts() {
        // Setup Test Data: Create an Account that has no children contacts
        Account emptyAcc = new Account(
            Name = 'Lonely Account LLC'
            
        );
        insert emptyAcc;

        // Execute Job
        Test.startTest();
        Database.executeBatch(new BusinessAccountMetricsBatch(), 200);
        Test.stopTest();

        // Verify that empty values fallback cleanly to 0 instead of causing NullPointerExceptions
        Account updatedAcc = [
            SELECT Clients_Referred__c, Prospects_Referred__c, Lifetime_Revenue__c, Business_Stage__c 
            FROM Account 
            WHERE Id = :emptyAcc.Id
        ];

        System.assertEquals(0, updatedAcc.Clients_Referred__c);
        System.assertEquals(0, updatedAcc.Prospects_Referred__c);
        System.assertEquals(0, updatedAcc.Lifetime_Revenue__c);
        System.assertEquals(null, updatedAcc.Business_Stage__c);
    }
}