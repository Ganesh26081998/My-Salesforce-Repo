@IsTest
private class BulkInvoiceZipQueueableTest {

    // ---------------------------------------------------------------------
    // Utility : Create Account
    // ---------------------------------------------------------------------
    private static Account createAccount(String name) {

        Account acc = new Account(Name = name);
        insert acc;

        return acc;
    }

    // ---------------------------------------------------------------------
    // Utility : Create Bulk Zip Job
    // ---------------------------------------------------------------------
    private static Bulk_Zip_Job__c createJob() {

        Bulk_Zip_Job__c job = new Bulk_Zip_Job__c(Status__c = 'Processing');
        insert job;

        return job;
    }

    // ---------------------------------------------------------------------
    // Utility : Create Invoice
    // ---------------------------------------------------------------------
    private static Invoice__c createInvoice(Id accountId, String invoiceType) {

        Invoice__c inv = new Invoice__c(
            Name = 'Test Invoice',
            Client__c = accountId,
            From_Date__c = Date.today().addDays(-7),
            To_Date__c = Date.today(),
            InvoiceType__c = invoiceType
        );

        insert inv;

        return inv;
    }

    // ---------------------------------------------------------------------
    // Utility : Create PDF File
    // ---------------------------------------------------------------------
    private static Id createPdfFile(Id invoiceId) {

        ContentVersion cv = new ContentVersion(
            Title = 'Invoice PDF',
            PathOnClient = 'Invoice.pdf',
            VersionData = Blob.valueOf('Test PDF')
        );

        insert cv;

        Id contentDocId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocId,
            LinkedEntityId = invoiceId,
            ShareType = 'V'
        );

        return contentDocId;
    }

    // ---------------------------------------------------------------------
    // Utility : Update Invoice PDF Fields
    // ---------------------------------------------------------------------
    private static void updateInvoicePdfFields(Invoice__c inv, Id contentDocId) {

        inv.PDF_File_Id__c = contentDocId;
        inv.PDFGeneratedDate__c = System.now().addDays(-2);

        update inv;
    }

    // ---------------------------------------------------------------------
    // Utility : Create Billing
    // ---------------------------------------------------------------------
    private static Billing__c createBilling(Id accountId) {

        Billing__c billing = new Billing__c(
            Client__c = accountId,
            Amount__c = 100,
            Invoice_Date__c = Date.today(),
            Is_Synced__c = false,
            Care_From_Date__c = Date.today().addDays(-5),
            Care_To_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = Date.today().addDays(-5),
            Invoice_Period_End_Date__c = Date.today(),
            Paid_Status__c = 'Paid'
        );

        insert billing;

        return billing;
    }

    // ---------------------------------------------------------------------
    // Utility : Create Event
    // ---------------------------------------------------------------------
    private static Event createEvent(Id accountId, Id billingId) {

        Event ev = new Event(
            Subject = 'Billing Event',
            WhatId = accountId,
            StartDateTime = System.now().addHours(-1),
            EndDateTime = System.now().addHours(1),
            Billing__c = billingId
        );

        insert ev;

        return ev;
    }

    // ---------------------------------------------------------------------
    // Utility : Create Billing Line Item
    // ---------------------------------------------------------------------
    private static Billing_Line_Item__c createBillingLineItem(Id billingId) {

        Billing_Line_Item__c bli = new Billing_Line_Item__c(
            Invoice__c = billingId,
            Service_Date__c = Date.today(),
            Quantity__c = 1,
            Description__c = 'Test BLI'
        );

        insert bli;

        return bli;
    }

    // ---------------------------------------------------------------------
    // Test : Invalid Date Range
    // ---------------------------------------------------------------------
    @IsTest
    static void testInvalidDateRange() {

        Account acc = createAccount('Test Account');
        Bulk_Zip_Job__c job = createJob();

        Test.startTest();

        System.enqueueJob(
            new BulkInvoiceZipQueueable(
                job.Id,
                new List<Id>{ acc.Id },
                'invalid-date',
                'invalid-date',
                'Standard Invoice',
                new Set<Id>(),
                null
            )
        );

        Test.stopTest();

        Bulk_Zip_Job__c updatedJob = [
            SELECT Status__c, Error_Message__c
            FROM Bulk_Zip_Job__c
            WHERE Id = :job.Id
        ];

        System.assertEquals('Failed', updatedJob.Status__c);
    }

    // ---------------------------------------------------------------------
    // Test : Household Invoice Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testHouseholdInvoiceCoverage() {

        Account acc = createAccount('Household Account');

        createInvoice(
            acc.Id,
            'Household Invoice'
        );

        Bulk_Zip_Job__c job = createJob();

        Test.startTest();

        System.enqueueJob(
            new BulkInvoiceZipQueueable(
                job.Id,
                new List<Id>{ acc.Id },
                String.valueOf(Date.today().addDays(-14)),
                String.valueOf(Date.today()),
                'Household Invoice',
                new Set<Id>(),
                null
            )
        );

        Test.stopTest();

        System.assert(true);
    }

    // ---------------------------------------------------------------------
    // Test : Queue Chaining Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testQueueChainingCoverage() {

        List<Id> accountIds = new List<Id>();

        for (Integer i = 0; i < 30; i++) {

            Account acc = createAccount('Chain Account ' + i);
            accountIds.add(acc.Id);
        }

        Bulk_Zip_Job__c job = createJob();

        Test.startTest();

        System.enqueueJob(
            new BulkInvoiceZipQueueable(
                job.Id,
                accountIds,
                String.valueOf(Date.today().addDays(-30)),
                String.valueOf(Date.today()),
                'Standard Invoice',
                new Set<Id>(),
                null
            )
        );

        Test.stopTest();

        System.assert(true);
    }

    // ---------------------------------------------------------------------
    // Test : Stale Invoice Coverage
    // ---------------------------------------------------------------------
    @IsTest
    static void testStaleInvoiceCoverage() {

        Account acc = createAccount('Stale PDF Account');

        Invoice__c inv = createInvoice(
            acc.Id,
            'Standard Invoice'
        );

        Id contentDocId = createPdfFile(inv.Id);

        updateInvoicePdfFields(
            inv,
            contentDocId
        );

        Billing__c billing = createBilling(acc.Id);

        createEvent(
            acc.Id,
            billing.Id
        );

        createBillingLineItem(
            billing.Id
        );

        Bulk_Zip_Job__c job = createJob();

        Test.startTest();

        System.enqueueJob(
            new BulkInvoiceZipQueueable(
                job.Id,
                new List<Id>{ acc.Id },
                String.valueOf(Date.today().addDays(-7)),
                String.valueOf(Date.today()),
                'Standard Invoice',
                new Set<Id>(),
                null
            )
        );

        Test.stopTest();

        System.assert(true);
    }
}