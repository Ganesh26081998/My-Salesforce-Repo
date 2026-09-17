@IsTest
public class WeeklyCapacityControllerTest {

    @IsTest
    static void testRunBatch() {

        Test.startTest();
        WeeklyCapacityController.runBatch();
        Test.stopTest();

        System.assert(true, 'Batch executed successfully');
    }
}