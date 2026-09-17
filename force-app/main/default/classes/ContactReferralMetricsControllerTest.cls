/*
----------------------------------------------------------------------------
Author        : Siva Naga Prasad
Class Name    : ContactReferralMetricsControllerTest
CreatedOn     : 14-05-2026
LastModifiedOn: 20-05-2026
LastModifiedBy: Siva Naga Prasad
Description   : Test class for ContactReferralMetricsController to validate 
                contact metric retrieval and batch execution.
----------------------------------------------------------------------------
*/

@IsTest
public class ContactReferralMetricsControllerTest {

    @IsTest
    static void testGetContactMetricsAndRunBatch() {

        // Step 1: Create test Contact
        Contact con = new Contact(
            LastName = 'Test Contact',
            Prospects_Referred__c = 5,
            Clients_Referred__c = 3,
            Lifetime_Revenue__c = 10000,
            Records_Updated_On__c = System.today()
        );
        insert con;

        // Step 2: Start Test (ONLY ONCE)
        Test.startTest();

        // Call method 1
        Contact result = ContactReferralMetricsController.getContactMetrics(con.Id);

        // Call method 2
        ContactReferralMetricsController.runBatch();

        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, result, 'Contact should not be null');
        System.assertEquals(5, result.Prospects_Referred__c);
        System.assertEquals(3, result.Clients_Referred__c);
        System.assertEquals(10000, result.Lifetime_Revenue__c);
    }
}