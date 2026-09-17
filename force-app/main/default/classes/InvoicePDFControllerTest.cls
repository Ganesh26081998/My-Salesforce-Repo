@IsTest
private class InvoicePDFControllerTest {

    // ---------------------------------------------------------------------
    // Utility : Create Account
    // ---------------------------------------------------------------------
    private static Account createAccount() {

        Account acc = new Account(
            Name = 'Test Client',
            Address_Prospect__c =
                '123 Main Street\nDallas TX'
        );

        insert acc;

        return acc;
    }

    // ---------------------------------------------------------------------
    // Test : Constructor Initialization
    // ---------------------------------------------------------------------
    @IsTest
    static void testConstructorInitialization() {

        Account acc = createAccount();

        Test.setCurrentPage(
            Page.InvoicePDF
        );

        ApexPages.currentPage().getParameters().put(
            'accountId',
            acc.Id
        );

        ApexPages.currentPage().getParameters().put(
            'fromDate',
            '05/01/2026'
        );

        ApexPages.currentPage().getParameters().put(
            'toDate',
            '05/10/2026'
        );

        ApexPages.currentPage().getParameters().put(
            'invoiceNo',
            'INV-1001'
        );

        Test.startTest();

        InvoicePDFController controller =
            new InvoicePDFController();

        Test.stopTest();

        System.assertEquals(
            acc.Id,
            controller.accountId
        );

        System.assertEquals(
            'INV-1001',
            controller.invoiceNo
        );

        System.assertNotEquals(
            null,
            controller.invoiceDate
        );

        System.assertNotEquals(
            null,
            controller.companyName
        );

        System.assertEquals(
            'Test Client',
            controller.clientName
        );

        System.assertNotEquals(
            null,
            controller.addressLines
        );
    }

    // ---------------------------------------------------------------------
    // Test : Phone Formatting Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testPhoneFormattingCoverage() {

        Account acc = createAccount();

        Test.setCurrentPage(
            Page.InvoicePDF
        );

        ApexPages.currentPage().getParameters().put(
            'accountId',
            acc.Id
        );

        ApexPages.currentPage().getParameters().put(
            'fromDate',
            '05/01/2026'
        );

        ApexPages.currentPage().getParameters().put(
            'toDate',
            '05/10/2026'
        );

        Test.startTest();

        InvoicePDFController controller =
            new InvoicePDFController();

        Test.stopTest();

        //System.assertNotEquals(null,controller.companyPhone);
    }

    // ---------------------------------------------------------------------
    // Test : Invoice Number Null Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testInvoiceNoNullCoverage() {

        Account acc = createAccount();

        Test.setCurrentPage(
            Page.InvoicePDF
        );

        ApexPages.currentPage().getParameters().put(
            'accountId',
            acc.Id
        );

        ApexPages.currentPage().getParameters().put(
            'fromDate',
            '05/01/2026'
        );

        ApexPages.currentPage().getParameters().put(
            'toDate',
            '05/10/2026'
        );

        Test.startTest();

        InvoicePDFController controller =
            new InvoicePDFController();

        Test.stopTest();

        System.assertEquals(
            '',
            controller.invoiceNo
        );
    }

    // ---------------------------------------------------------------------
    // Test : Address Wrapping Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testAddressWrappingCoverage() {

        Account acc = createAccount();

        Test.setCurrentPage(
            Page.InvoicePDF
        );

        ApexPages.currentPage().getParameters().put(
            'accountId',
            acc.Id
        );

        ApexPages.currentPage().getParameters().put(
            'fromDate',
            '05/01/2026'
        );

        ApexPages.currentPage().getParameters().put(
            'toDate',
            '05/10/2026'
        );

        Test.startTest();

        InvoicePDFController controller =
            new InvoicePDFController();

        Test.stopTest();

        System.assert(
            controller.addressLines.size() > 0
        );
    }
}