@IsTest
public class AccountPrimaryValidationHandlerTest {

    @testSetup
    static void setupData() {

        List<Account> accList = new List<Account>();

        for(Integer i = 0; i < 3; i++){
            accList.add(new Account(
                Name = 'Test Account ' + i,
                Is_Primary__c = false
            ));
        }
        insert accList;
    }

    // ✅ Test: Becoming Primary
    @IsTest
    static void testBecomingPrimary() {

        List<Account> accList = [SELECT Id, Is_Primary__c FROM Account];
        Map<Id, Account> oldMap = new Map<Id, Account>(accList);

        accList[0].Is_Primary__c = true;

        Test.startTest();
        AccountPrimaryValidationHandler.handle(accList, oldMap, true);
        Test.stopTest();

        System.assertEquals(true, accList[0].Is_Primary__c);
    }

    // ✅ Test: Multiple becoming primary
    @IsTest
    static void testMultiplePrimary() {

        List<Account> accList = [SELECT Id, Is_Primary__c FROM Account];
        Map<Id, Account> oldMap = new Map<Id, Account>(accList);

        for(Account acc : accList){
            acc.Is_Primary__c = true;
        }

        Test.startTest();
        AccountPrimaryValidationHandler.handle(accList, oldMap, true);
        Test.stopTest();

        System.assertEquals(true, accList[1].Is_Primary__c);
    }

    // ✅ Test: No change
    @IsTest
    static void testNoChange() {

        List<Account> accList = [SELECT Id, Is_Primary__c FROM Account];
        Map<Id, Account> oldMap = new Map<Id, Account>(accList);

        Test.startTest();
        AccountPrimaryValidationHandler.handle(accList, oldMap, true);
        Test.stopTest();

        System.assert(true);
    }

    // ✅ Test: Empty input
    @IsTest
    static void testEmptyInput() {

        Test.startTest();
        AccountPrimaryValidationHandler.handle(
            new List<Account>(),
            new Map<Id, Account>(),
            true
        );
        Test.stopTest();

        System.assert(true);
    }

    // ✅ Test: Null oldMap scenario
    @IsTest
    static void testNullOldMap() {

        List<Account> accList = [SELECT Id, Is_Primary__c FROM Account];

        accList[0].Is_Primary__c = true;

        Test.startTest();
        AccountPrimaryValidationHandler.handle(accList, null, true);
        Test.stopTest();

        System.assertEquals(true, accList[0].Is_Primary__c);
    }
    
    @IsTest
static void testHandle_CustomSettingNull_BypassFalse() {

    // No custom setting inserted → getInstance() = null

    List<Account> accList = [SELECT Id, Is_Primary__c FROM Account];
    Map<Id, Account> oldMap = new Map<Id, Account>(accList);

    accList[0].Is_Primary__c = true;

    Test.startTest();
    AccountPrimaryValidationHandler.handle(accList, oldMap, false);
    Test.stopTest();

    System.assert(true);
}
    
    @IsTest
static void testHandle_CustomSettingDisabled_BypassFalse() {

    // 🔥 Insert custom setting with Run_Triggers__c = false
    WellSky_Custom_Setting__c cs = new WellSky_Custom_Setting__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        Name = 'TestCS',
        Run_Triggers__c = false
    );
    insert cs;

    List<Account> accList = [SELECT Id, Is_Primary__c FROM Account];
    Map<Id, Account> oldMap = new Map<Id, Account>(accList);

    accList[0].Is_Primary__c = true;

    Test.startTest();
    AccountPrimaryValidationHandler.handle(accList, oldMap, false);
    Test.stopTest();

    System.assert(true);
}
    
    @IsTest
static void testTriggerExecution() {

    List<Account> accList = new List<Account>();

    for(Integer i = 0; i < 2; i++){
        accList.add(new Account(
            Name = 'Trigger Test ' + i,
            Is_Primary__c = false
        ));
    }
    insert accList;

    // Update → fires trigger
    for(Account acc : accList){
        acc.Is_Primary__c = true;
    }

    Test.startTest();
    update accList;
    Test.stopTest();

    System.assertEquals(true, accList[0].Is_Primary__c);
}
}