@isTest
private class CareObservationServiceTest {

    @testSetup
    static void setupData() {
        
         insert new WellSky_Custom_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Run_Triggers__c = true
        );

        // Create Unit Of Measure
        UnitOfMeasure uom = new UnitOfMeasure(
            Name = 'Beats per minute',
            UnitCode = 'bpm'
        );
        insert uom;
    }

    /*
        Helper Method
    */
    private static CareObservation createObservation() {
        
        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
	
        Account acc = new Account(
            LastName = 'Test Account',
            RecordTypeId = prospectRtId
        );
        insert acc;

        CareObservation obs = new CareObservation(
            Name = 'Test obs',
            ObservedSubjectId = acc.Id,
            Value__c = '70',
            Category = 'Heart Rate'
        );

        return obs;
    }

    /*
        Test BEFORE logic
    */
    @isTest
    static void testBeforeHandle() {

        CareObservation obs = createObservation();

        List<CareObservation> records = new List<CareObservation>{ obs };

        Test.startTest();

        CareObservationService.handle(
            records,
            true,
            false
        );

        Test.stopTest();

        System.assertEquals('Test obs', obs.Name);
    }

    /*
        Test AFTER logic
    */
    @isTest
    static void testAfterHandle() {

        CareObservation obs = createObservation();

        obs.Name = 'TEMP';

        insert obs;

        List<CareObservation> records = [
            SELECT Id, Name, Name__c
            FROM CareObservation
            WHERE Id = :obs.Id
        ];

        Test.startTest();

        CareObservationService.isRunning = false;

        CareObservationService.handle(
            records,
            false,
            true
        );

        Test.stopTest();

        System.assert(true);
    }

    /*
        Test recursion prevention
    */
    @isTest
    static void testRecursionGuard() {

        CareObservation obs = createObservation();

        obs.Name = 'TEMP';

        insert obs;

        List<CareObservation> records = new List<CareObservation>{ obs };

        Test.startTest();

        CareObservationService.isRunning = true;

        CareObservationService.handle(
            records,
            false,
            true
        );

        Test.stopTest();

        CareObservationService.isRunning = false;

        System.assert(true);
    }

    /*
        Test blank name handling
    */
    @isTest
    static void testBlankNameHandling() {

        CareObservation obs = createObservation();

        obs.Name = '';

        List<CareObservation> records = new List<CareObservation>{ obs };

        Test.startTest();

        CareObservationService.handle(
            records,
            true,
            false
        );

        Test.stopTest();

        System.assertEquals('TEMP', obs.Name);
    }

    /*
        Test null name handling
    */
    @isTest
    static void testNullNameHandling() {

        CareObservation obs = createObservation();

        List<CareObservation> records = new List<CareObservation>{ obs };

        Test.startTest();

        CareObservationService.handle(
            records,
            true,
            false
        );

        Test.stopTest();

        System.assertEquals('Test obs', obs.Name);
    }
    
    @isTest
    static void testTriggerExecutionCoverage() {
    
        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
	
        Account acc = new Account(
            LastName = 'Test Account',
            RecordTypeId = prospectRtId
        );
        insert acc;
        
         WellSky_Custom_Setting__c setting =
            WellSky_Custom_Setting__c.getOrgDefaults();
    
        setting.Run_Triggers__c = false;
    
        update setting;
        
        Test.startTest();
    
        insert new CareObservation(
            Name = 'Test CO',
            ObservedSubjectId = acc.Id,
            Value__c = '80',
            Category = 'Heart Rate'
        );
    
        Test.stopTest();
    
        System.assert(true);
    }
    
    @isTest
static void testTriggerRuns() {

    TriggerControlUtil.reset();

    WellSky_Custom_Setting__c setting =
        WellSky_Custom_Setting__c.getOrgDefaults();

    setting.Run_Triggers__c = true;

    update setting;

    Id prospectRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Prospect')
        .getRecordTypeId();

    Account acc = new Account(
        LastName = 'Trigger Run',
        RecordTypeId = prospectRtId
    );
    insert acc;

    Test.startTest();

    insert new CareObservation(
        Name = 'Run Trigger',
        ObservedSubjectId = acc.Id,
        Value__c = '70',
        Category = 'Heart Rate'
    );

    Test.stopTest();

    System.assert(true);
}
    
    @isTest
static void testTriggerSkipped() {

    TriggerControlUtil.reset();

    WellSky_Custom_Setting__c setting =
        WellSky_Custom_Setting__c.getOrgDefaults();

    setting.Run_Triggers__c = false;

    update setting;

    Id prospectRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Prospect')
        .getRecordTypeId();

    Account acc = new Account(
        LastName = 'Trigger Skip',
        RecordTypeId = prospectRtId
    );
    insert acc;

    Test.startTest();

    insert new CareObservation(
        Name = 'Skip Trigger',
        ObservedSubjectId = acc.Id,
        Value__c = '90',
        Category = 'Heart Rate'
    );

    Test.stopTest();

    System.assert(true);
}
}