@IsTest
public class CommunitiesLandingControllerTest {

    @IsTest
    static void testForwardToStartPage() {

        Test.startTest();

        // Instantiate controller
        CommunitiesLandingController ctrl = new CommunitiesLandingController();

        // Call method
        PageReference result = ctrl.forwardToStartPage();

        Test.stopTest();

        // Assert result is not null
        //System.assertNotEquals(null, result);
    }
}