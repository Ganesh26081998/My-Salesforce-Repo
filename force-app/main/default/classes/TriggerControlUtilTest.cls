@IsTest
private class TriggerControlUtilTest {

    // ---------------------------------------------------------------------
    // Test : shouldRun returns TRUE
    // ---------------------------------------------------------------------
    @IsTest
    static void testShouldRun_True() {

        // Reset cached value
        TriggerControlUtil.reset();

        WellSky_Custom_Setting__c setting =
            new WellSky_Custom_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Run_Triggers__c = true
            );

        upsert setting;

        Test.startTest();

        Boolean result =
            TriggerControlUtil.shouldRun();

        Test.stopTest();

        System.assertEquals(
            true,
            result
        );
    }

    // ---------------------------------------------------------------------
    // Test : shouldRun returns FALSE
    // ---------------------------------------------------------------------
    @IsTest
    static void testShouldRun_False() {

        // Reset cached value
        TriggerControlUtil.reset();

        WellSky_Custom_Setting__c setting =
            new WellSky_Custom_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Run_Triggers__c = false
            );

        upsert setting;

        Test.startTest();

        Boolean result =
            TriggerControlUtil.shouldRun();

        Test.stopTest();

        System.assertEquals(
            false,
            result
        );
    }

    // ---------------------------------------------------------------------
    // Test : Cached Value Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testShouldRun_CacheCoverage() {

        TriggerControlUtil.reset();

        WellSky_Custom_Setting__c setting =
            new WellSky_Custom_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Run_Triggers__c = true
            );

        upsert setting;

        Test.startTest();

        Boolean firstCall =
            TriggerControlUtil.shouldRun();

        Boolean secondCall =
            TriggerControlUtil.shouldRun();

        Test.stopTest();

        System.assertEquals(
            true,
            firstCall
        );

        System.assertEquals(
            true,
            secondCall
        );
    }
    
}