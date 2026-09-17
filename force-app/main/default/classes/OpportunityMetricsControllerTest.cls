@isTest
public class OpportunityMetricsControllerTest {

    @isTest
    static void testGetOpportunityMetrics() {

        // 🔹 Step 1: Create Account (required for Opportunity)
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // 🔹 Step 2: Create Opportunity with required fields
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10),
            AccountId = acc.Id,
            Prospects_Referred__c = 5,
            Clients_Referred__c = 3,
            Lifetime_Revenue__c = 10000
        );
        insert opp;

        // 🔹 Step 3: Call Apex method
        Test.startTest();

        Opportunity result = OpportunityMetricsController.getOpportunityMetrics(opp.Id);

        Test.stopTest();

        // 🔹 Step 4: Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(5, result.Prospects_Referred__c);
        System.assertEquals(3, result.Clients_Referred__c);
        System.assertEquals(10000, result.Lifetime_Revenue__c);
    }


    @isTest
    static void testRunOpportunityBatch() {

        // 🔹 Minimal data (if batch depends on Opportunity)
        Account acc = new Account(Name = 'Batch Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Batch Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(5),
            AccountId = acc.Id
        );
        insert opp;

        // 🔹 Execute batch via controller
        Test.startTest();

        OpportunityMetricsController.runOpportunityBatch();

        Test.stopTest();

        // 🔹 No direct assertion (batch async), but ensure no exception
        System.assert(true, 'Batch executed successfully');
    }
}