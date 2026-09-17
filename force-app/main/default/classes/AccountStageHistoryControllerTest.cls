@IsTest
public class AccountStageHistoryControllerTest {

    // ---------------------------------------------------------------------
    // Utility : Create Account
    // ---------------------------------------------------------------------
    private static Account createAccount() {
        
         Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();

        Account acc = new Account(
            LastName = 'Test Account',
            Account_Status__c = 'Client',
            NewInquiryDate__c = Date.today().addDays(-10),
            OutreachInprogressDate__c = Date.today().addDays(-8),
            ProspectDate__c = Date.today().addDays(-6),
            AssessmentScheduledStageDate__c = Date.today().addDays(-4),
            AssessmentCompletedStageDate__c = Date.today().addDays(-2),
            ClientDate__c = Date.today(),
            RecordTypeId = prospectRtId
        );

        insert acc;

        return acc;
    }

    // ---------------------------------------------------------------------
    // Test : Stage History With Dates
    // ---------------------------------------------------------------------
    @IsTest
    static void testGetStageHistory_WithDates() {

        Account acc = createAccount();

        Test.startTest();

        Map<String, Object> result =
            AccountStageHistoryController.getStageHistory(acc.Id);

        Test.stopTest();

        // Extract history map
        Map<String, String> history =
            (Map<String, String>) result.get('history');

        String createdDate =
            (String) result.get('createdDate');

        // Assertions
        System.assertNotEquals(
            null,
            history
        );

        System.assertEquals(
            true,
            history.containsKey('New Inquiry')
        );

        System.assertEquals(
            true,
            history.containsKey('Client')
        );

        System.assertNotEquals(
            null,
            history.get('Client')
        );

        System.assertNotEquals(
            null,
            createdDate
        );
    }

    // ---------------------------------------------------------------------
    // Test : Stage History Without Dates
    // ---------------------------------------------------------------------
    @IsTest
    static void testGetStageHistory_NoDates() {

        Account acc = new Account(
            Name = 'No Dates Account'
        );

        insert acc;

        Test.startTest();

        Map<String, Object> result =
            AccountStageHistoryController.getStageHistory(acc.Id);

        Test.stopTest();

        Map<String, String> history =
            (Map<String, String>) result.get('history');

        System.assertEquals(
            null,
            history.get('New Inquiry')
        );

        System.assertEquals(
            null,
            history.get('Client')
        );
    }

    // ---------------------------------------------------------------------
    // Test : Invalid Account Id
    // ---------------------------------------------------------------------
    @IsTest
    static void testGetStageHistory_InvalidId() {

        Test.startTest();

        try {

            AccountStageHistoryController.getStageHistory(
                '001000000000000AAA'
            );

            System.assert(
                false,
                'Exception expected'
            );

        } catch (Exception e) {

            System.assertNotEquals(
                null,
                e.getMessage()
            );
        }

        Test.stopTest();
    }
}