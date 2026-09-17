@IsTest
public class QuickBooksExceptionTest {

    @IsTest
    static void testQuickBooksException() {

        Test.startTest();

        try {
            // Throw custom exception
            throw new QuickBooksException('Test Exception');

        } catch (QuickBooksException ex) {

            // Verify exception message
            System.assertEquals('Test Exception', ex.getMessage());
        }

        Test.stopTest();
    }
}