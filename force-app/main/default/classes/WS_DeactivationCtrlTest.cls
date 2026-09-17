@IsTest
public class WS_DeactivationCtrlTest {

    @testSetup
    static void setupData() {

        Account acc = new Account(
            Name = 'Test Account',
            Is_Deactivated__c = false
        );
        insert acc;

        Account_Deactivation__c deact = new Account_Deactivation__c(
            Name = 'Test Deactivation',
            Account__c = acc.Id,
            Deactivation_Date__c = Date.today(),
            Deactivation_Reason__c = 'Other',
            Deactivation_summary__c = 'Test Summary'
        );

        Map<String, Schema.SObjectField> fieldsMap =
            Account_Deactivation__c.SObjectType.getDescribe().fields.getMap();

        if(fieldsMap.containsKey('Other_Reason__c')){
            deact.put('Other_Reason__c', 'Test Other Reason');
        }

        insert deact;
    }

    @IsTest
    static void testAllMethods() {

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();

        // isAccountDeactivated
        Boolean isDeact =
            WellSpringAccountDeactivationController.isAccountDeactivated(acc.Id);

        // getLatestDeactivationData
        Map<String, Object> data =
            WellSpringAccountDeactivationController.getLatestDeactivationData(acc.Id);

        // null case
        WellSpringAccountDeactivationController.getLatestDeactivationData(null);

        // picklist
        List<String> options =
            WellSpringAccountDeactivationController.getDeactivationReasonOptions();

        // create record
        WellSpringAccountDeactivationController.createDeactivationRecord(
            acc.Id,
            'New Deactivation',
            Date.today(),
            'Other',
            'Other reason',
            'Summary'
        );

        // async
        WellSpringAccountDeactivationController.lockAccountAsync(acc.Id);

        Test.stopTest();

        System.assertNotEquals(null, data);
    }
}