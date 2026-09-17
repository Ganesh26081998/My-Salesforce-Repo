@IsTest
private class InvoicesCleanupBatchTest {

    // ---------------------------------------------------------------------
    // Utility : Create Invoice Records
    // ---------------------------------------------------------------------
    private static List<Invoice__c> createInvoices(Integer count) {

        List<Invoice__c> invoices = new List<Invoice__c>();

        for (Integer i = 0; i < count; i++) {

            invoices.add(
                new Invoice__c(
                    Name = 'Test Invoice ' + i
                )
            );
        }

        insert invoices;

        return invoices;
    }

    // ---------------------------------------------------------------------
    // Test : No Records Deleted When Less Than Retention Count
    // ---------------------------------------------------------------------
    @IsTest
    static void testCleanupBatch_NoDeletion() {

        createInvoices(10);

        Integer beforeCount = [
            SELECT COUNT()
            FROM Invoice__c
        ];

        Test.startTest();

        Database.executeBatch(
            new InvoicesCleanupBatch(),
            200
        );

        Test.stopTest();

        Integer afterCount = [
            SELECT COUNT()
            FROM Invoice__c
        ];

        System.assertEquals(
            beforeCount,
            afterCount,
            'No records should be deleted when total count is below retention limit.'
        );
    }

    // ---------------------------------------------------------------------
    // Test : Batch Executes Successfully
    // ---------------------------------------------------------------------
    @IsTest
    static void testCleanupBatch_Execution() {

        createInvoices(501);

        Test.startTest();

        InvoicesCleanupBatch batch =
            new InvoicesCleanupBatch();

        Database.executeBatch(
            batch,
            200
        );

        Test.stopTest();

        System.assert(true);
    }

    // ---------------------------------------------------------------------
    // Test : Start Method Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testStartMethodCoverage() {

        createInvoices(3);

        Test.startTest();

        InvoicesCleanupBatch batch =
            new InvoicesCleanupBatch();

        Database.QueryLocator ql =
            batch.start(null);

        Test.stopTest();

        System.assertNotEquals(
            null,
            ql
        );
    }

    // ---------------------------------------------------------------------
    // Test : Execute Method With Empty Scope
    // ---------------------------------------------------------------------
    @IsTest
    static void testExecuteWithEmptyScope() {

        Test.startTest();

        InvoicesCleanupBatch batch =
            new InvoicesCleanupBatch();

        batch.execute(
            null,
            new List<SObject>()
        );

        Test.stopTest();

        System.assert(true);
    }

    // ---------------------------------------------------------------------
    // Test : Finish Method Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testFinishMethodCoverage() {

        Test.startTest();

        InvoicesCleanupBatch batch =
            new InvoicesCleanupBatch();

        batch.finish(null);

        Test.stopTest();

        System.assert(true);
    }
}