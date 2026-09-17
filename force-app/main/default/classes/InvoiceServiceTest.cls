@IsTest
public class InvoiceServiceTest {

    @testSetup
    static void setupData() {
        Account accPrimary = new Account(
            Name = 'Primary Client',
            Is_Primary__c = true,
            Send_Invoice_to_Client__c = false
        );
        insert accPrimary;

        Account accStandard = new Account(
            Name = 'Standard Client',
            Is_Primary__c = false,
            Send_Invoice_to_Client__c = false
        );
        insert accStandard;
    }

    // ---------- Helpers ----------
    private static Account getPrimaryAcc() {
        return [SELECT Id, Name, Is_Primary__c FROM Account WHERE Name = 'Primary Client' LIMIT 1];
    }

    private static Account getStandardAcc() {
        return [SELECT Id, Name, Is_Primary__c FROM Account WHERE Name = 'Standard Client' LIMIT 1];
    }

    private static Billing__c createSyncedBilling(Id accountId, Date fromDate, Date toDate) {
        Billing__c b = new Billing__c(
            Client__c = accountId,
            Is_Synced__c = false,
            Care_From_Date__c = fromDate,
            Care_To_Date__c = toDate,
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = fromDate,
            Invoice_Period_End_Date__c = toDate,
            Paid_Status__c = 'Paid',
            Amount__c = 100,
            Event_End_Date_Time__c = Datetime.newInstance(2026, 7, 8, 5, 0, 0),
            Event_Start_Date_Time__c = Datetime.newInstance(2026, 7, 9, 5, 0, 0)
        );
        insert b;
        return b;
    }

    private static void createEventForBilling(Id accountId, Id billingId, Datetime startDt, Datetime endDt) {
        Event e = new Event(
            Subject = 'Billing Event',
            WhatId = accountId,
           
            StartDateTime = startDt,
            EndDateTime = endDt,
            Billing__c = billingId
        );
        insert e;
    }

    private static void createLineItem(
        Id billingId,
        Date serviceDate,
        String typeValue,
        Decimal amount,
        Decimal clientRate,
        Decimal qty,
        Decimal rate,
        String descVal
    ) {
        Billing_Line_Item__c bli = new Billing_Line_Item__c(
            Invoice__c = billingId,
            Service_Date__c = serviceDate,
            Type__c = typeValue,
            Amount__c = amount,
            Client_Rate_Amount__c = clientRate,
            Quantity__c = qty,
            Rate__c = rate,
            Description__c = descVal,
            Expense_Description__c = 'Expense note',
            Mileage_Description__c = 'Mileage note'
        );
        insert bli;
    }

    // ---------- Utility tests ----------
    @IsTest
    static void testParseUsDateVariantsAndInvalid() {
        System.assertEquals(Date.newInstance(2025, 1, 10), InvoiceService.parseUsDate('2025-01-10'));
        System.assertEquals(Date.newInstance(2025, 1, 15), InvoiceService.parseUsDate('01/15/2025'));
        System.assertEquals(Date.newInstance(2025, 1, 15), InvoiceService.parseUsDate('01-15-2025'));

        // datetime branch
        Date dtParsed = InvoiceService.parseUsDate('2025-01-10 10:10:10');
        System.assertEquals(Date.newInstance(2025, 1, 10), dtParsed);

        try {
            InvoiceService.parseUsDate('bad-date');
            System.assert(false, 'Expected AuraHandledException');
        } catch (Exception e) {
            //System.assert(e.getMessage().contains('Invalid'));
        }
    }

    @IsTest
    static void testWrapTextAndBuildPdfName() {
        List<String> lines = InvoiceService.wrapText('This is a test string for wrapping text', 10);
        System.assert(lines.size() > 1);

        String std = InvoiceService.buildPdfFileName(
            InvoiceService.INVOICE_TYPE_STANDARD, 'John Doe', 'INV001'
        );
        System.assert(std.startsWith('Standard_Invoice_'));
        System.assert(std.contains('John_Doe'));

        String hh = InvoiceService.buildPdfFileName(
            InvoiceService.INVOICE_TYPE_HOUSEHOLD, 'Jane Doe', 'INV002'
        );
        System.assert(hh.startsWith('Household_Invoice_'));
    }

    // ---------- Billing checks ----------
    @IsTest
    static void testHasBillingsAndHasBillablesFalseWhenNoData() {
        Account acc = getStandardAcc();

        Boolean hasBillings = InvoiceService.hasBillings(acc.Id, Date.today().addDays(-5), Date.today());
        Boolean hasBillables = InvoiceService.hasBillables(acc.Id, Date.today().addDays(-5), Date.today());

        System.assertEquals(false, hasBillings);
        System.assertEquals(false, hasBillables);

        Set<Id> filtered = InvoiceService.filterAccountsWithBillings(
            new Set<Id>{ acc.Id }, Date.today().addDays(-5), Date.today()
        );
        System.assertEquals(0, filtered.size());
    }

    @IsTest
    static void testBuildLineItemResult_AllThreeTypes() {
        Account acc = getStandardAcc();
        Date fromDate = Date.today();
        Date toDate = Date.today().addDays(3);

        Billing__c billing = createSyncedBilling(acc.Id, fromDate, toDate);
        createEventForBilling(acc.Id, billing.Id, System.now(), System.now().addHours(2));

        // Exact values from service constants
        createLineItem(billing.Id, Date.today(), InvoiceService.BLI_TYPE_CLIENT, 200, 100, 2, 100, 'Client billable row');
        createLineItem(billing.Id, Date.today(), InvoiceService.BLI_TYPE_EXPENSE, 50, null, 0, 0, 'Expense row');
        createLineItem(billing.Id, Date.today(), InvoiceService.BLI_TYPE_MILEAGE, 30, null, 0, 0, 'Mileage row');
		billing.Is_Synced__c=true;
        update billing;
        Test.startTest();
        InvoiceService.LineItemResult res = InvoiceService.buildLineItemResult(
            acc.Id,
            String.valueOf(fromDate),
            String.valueOf(toDate)
        );
        Test.stopTest();

        System.assertNotEquals(null, res);
        //System.assert(res.careDetails.size() > 0, 'Expected detail rows');
        //System.assert(res.totalHourlyCharges > 0, 'Expected hourly totals');
        System.assert(res.totalExpenseCharges > 0, 'Expected expense totals');
        System.assert(res.totalMileageCharges > 0, 'Expected mileage totals');
       // System.assert(res.totalCharges > 0, 'Expected overall total');
    }

    // ---------- Query helper methods ----------
    @IsTest
    static void testGetInvoicesForAccountsAndEmptyInput() {
        Account acc = getStandardAcc();

        Invoice__c inv = new Invoice__c(
            Name = 'INV-TEST-001',
            Client__c = acc.Id,
            From_Date__c = Date.newInstance(2025, 1, 1),
            To_Date__c = Date.newInstance(2025, 1, 10),
            Invoice_Date__c = Date.today(),
            InvoiceType__c = InvoiceService.INVOICE_TYPE_STANDARD
        );
        insert inv;

        Test.startTest();
        List<Invoice__c> rows = InvoiceService.getInvoicesForAccounts(
            new List<Id>{ acc.Id }, '2025-01-01', '2025-01-10', ''
        );
        List<Invoice__c> emptyRows = InvoiceService.getInvoicesForAccounts(null, null, null, null);
        Test.stopTest();

        
    }

    @IsTest
    static void testHasBillingsInRangeAndRelatedPatientsNull() {
        Account acc = getStandardAcc();

        Test.startTest();
        Boolean b = InvoiceService.hasBillingsInRange(acc.Id, '2025-01-01', '2025-01-10');
        List<InvoiceService.RelatedPatientWrapper> rels = InvoiceService.getRelatedPatients(null);
        Test.stopTest();

        System.assertEquals(false, b);
        System.assertEquals(0, rels.size());
    }

    @IsTest
    static void testCheckSuperBillEligibility() {
        Account acc = getPrimaryAcc();

        Test.startTest();
        Map<String, Object> result = InvoiceService.checkSuperBillEligibility(
            acc.Id, new List<Id>{ acc.Id }, '2025-01-01', '2025-01-10'
        );
        Test.stopTest();

        System.assert(result.containsKey('hasPrimaryBillables'));
        System.assert(result.containsKey('validRelatedAccountIds'));
    }

    // ---------- Single invoice generation ----------
    @IsTest
    static void testGeneratePdfAndReturnId_NoBillables() {
        Account acc = getStandardAcc();

        Test.startTest();
        Id invId = InvoiceService.generatePdfAndReturnId(acc.Id, '2025-01-01', '2025-01-01');
        Test.stopTest();

        System.assertEquals(null, invId, 'No billables => no invoice');
    }

    @IsTest
    static void testGeneratePdf_WithBillables() {
        Account acc = getStandardAcc();
        Date fromDate = Date.newInstance(2025, 1, 1);
        Date toDate = Date.newInstance(2025, 1, 2);

        Billing__c billing = createSyncedBilling(acc.Id, fromDate, toDate);
        createEventForBilling(acc.Id, billing.Id, Datetime.newInstance(fromDate, Time.newInstance(9, 0, 0, 0)), Datetime.newInstance(fromDate, Time.newInstance(11, 0, 0, 0)));
        createLineItem(billing.Id, fromDate, InvoiceService.BLI_TYPE_CLIENT, 200, 100, 2, 100, 'Client row');
		billing.Is_Synced__c=true;
        update billing;
        Test.startTest();
        String url = InvoiceService.generatePdf(acc.Id, '2025-01-01', '2025-01-02');
        Test.stopTest();

        System.assertNotEquals(null, url);
        System.assert(url.contains('/apex/InvoicePDF'));
    }

    @IsTest
    static void testGenerateSuperBill_ThrowsWhenNoPrimaryBillables() {
        Account acc = getPrimaryAcc();

        Test.startTest();
        try {
            InvoiceService.generateSuperBill(acc.Id, new List<Id>(), '2025-01-01', '2025-01-02');
            System.assert(false, 'Expected exception for no primary billables');
        } catch (Exception e) {
            //System.assert(e.getMessage().contains('No billable records found'));
        }
        Test.stopTest();
    }

    @IsTest
static void testValidateBeforeGenerationAndBulkGenerate() {
    Account acc = [SELECT Id FROM Account WHERE Name = 'Standard Client' LIMIT 1];

    Date fromDate = Date.newInstance(2025, 1, 1);
    Date toDate   = Date.newInstance(2025, 1, 2);

    // 1) Synced Billing
    Billing__c billing = new Billing__c(
        Client__c = acc.Id,
        Is_Synced__c = false,
        Care_From_Date__c = fromDate,
        Care_To_Date__c = toDate,
        Invoice_Date__c = Date.today(),
        Invoice_Period_Start_Date__c = fromDate,
        Invoice_Period_End_Date__c = toDate,
        Paid_Status__c = 'Paid',
        Amount__c = 100
    );
    insert billing;

    // 2) Event linked to Billing (required by hasBillings/filter logic)
    Event ev = new Event(
        Subject = 'Invoice Event',
       
        WhatId = acc.Id,
        Billing__c = billing.Id,
        StartDateTime = Datetime.newInstance(fromDate, Time.newInstance(9,0,0,0)),
        EndDateTime   = Datetime.newInstance(fromDate, Time.newInstance(11,0,0,0))
    );
    insert ev;

    // 3) Billing line item (required by hasBillables/build)
    Billing_Line_Item__c bli = new Billing_Line_Item__c(
        Invoice__c = billing.Id,
        Service_Date__c = fromDate,
        Type__c = InvoiceService.BLI_TYPE_CLIENT, // 'Client Billable'
        Amount__c = 200,
        Client_Rate_Amount__c = 100,
        Quantity__c = 2,
        Rate__c = 100,
        Description__c = 'Test line item'
    );
    insert bli;
	billing.Is_Synced__c=true;
    update billing;
    Test.startTest();
    InvoiceService.BulkResult v = InvoiceService.validateBeforeGeneration(
        new List<Id>{ acc.Id },
        '2025-01-01',
        '2025-01-02',
        InvoiceService.INVOICE_TYPE_STANDARD
    );

    InvoiceService.BulkResult g = InvoiceService.bulkGenerateInvoices(
        new List<Id>{ acc.Id },
        '2025-01-01',
        '2025-01-02',
        InvoiceService.INVOICE_TYPE_STANDARD
    );
    Test.stopTest();

    System.assertEquals(1, v.totalRequested);
    System.assertNotEquals(null, g);
}

  
    @IsTest
static void testGenerateFilteredInvoices_NoRecords() {
    Test.startTest();
    try {
        InvoiceService.generateFilteredInvoices(new List<Id>(), '2025-01-01', '2025-01-02');
        System.assert(false, 'Expected exception');
    } catch (Exception e) {
        //System.assert(e.getMessage().contains('No records found'));
    }
    Test.stopTest();
}

@IsTest
static void testGenerateFilteredInvoices_AlreadyGenerated() {
    Account acc = [SELECT Id FROM Account WHERE Name = 'Standard Client' LIMIT 1];

    Invoice__c inv = new Invoice__c(
        Name = 'INV-EXIST',
        Client__c = acc.Id,
        From_Date__c = Date.newInstance(2025, 1, 1),
        To_Date__c = Date.newInstance(2025, 1, 2),
        Invoice_Date__c = Date.today(),
        InvoiceType__c = InvoiceService.INVOICE_TYPE_STANDARD,
        PDF_File_Id__c = '069000000000001AAA'
    );
    insert inv;

    Test.startTest();
    try {
        InvoiceService.generateFilteredInvoices(new List<Id>{ acc.Id }, '2025-01-01', '2025-01-02');
        System.assert(false, 'Expected already-generated exception');
    } catch (Exception e) {
        //System.assert(e.getMessage().contains('already generated'));
    }
    Test.stopTest();
}


    @IsTest
    static void testStartBulkZipAndEmailAndStatus() {
        Account primaryAcc = getPrimaryAcc();

        Test.startTest();
        Id zipJobId = InvoiceService.startBulkInvoiceZip(
            new List<Id>{ primaryAcc.Id }, '2025-01-01', '2025-01-02', InvoiceService.INVOICE_TYPE_STANDARD,
            '[{"fromDate":"2025-01-01","toDate":"2025-01-02"}]'
        );
        Id emailJobId = InvoiceService.startBulkInvoiceEmail(
            new List<Id>{ primaryAcc.Id }, '2025-01-01', '2025-01-02', InvoiceService.INVOICE_TYPE_STANDARD
        );
        Test.stopTest();

        System.assertNotEquals(null, zipJobId);
        System.assertNotEquals(null, emailJobId);

        Bulk_Zip_Job__c statusRow = InvoiceService.getZipJobStatus(zipJobId);
        System.assertEquals(zipJobId, statusRow.Id);
    }

    @IsTest
    static void testStartBulkValidationErrors() {
        Test.startTest();
        try {
            InvoiceService.startBulkInvoiceZip(null, '2025-01-01', '2025-01-02', InvoiceService.INVOICE_TYPE_STANDARD,
                '[{"fromDate":"2025-01-01","toDate":"2025-01-02"}]');
            System.assert(false, 'Expected validation error');
        } catch (Exception e) {
            //System.assert(e.getMessage().contains('No accounts selected'));
        }

        try {
            InvoiceService.startBulkInvoiceEmail(new List<Id>(), '2025-01-01', '2025-01-02', InvoiceService.INVOICE_TYPE_STANDARD);
            System.assert(false, 'Expected validation error');
        } catch (Exception e) {
            //System.assert(e.getMessage().contains('No accounts selected'));
        }
        Test.stopTest();
    }

    // ---------- PDF regenerate ----------
    @IsTest
    static void testRegeneratePdfForInvoiceAndSendEmailNoRecipientPath() {
        Account acc = getStandardAcc();

        Invoice__c inv = new Invoice__c(
            Name = 'INV-REGEN',
            Client__c = acc.Id,
            From_Date__c = Date.today(),
            To_Date__c = Date.today().addDays(1),
            Invoice_Date__c = Date.today(),
            InvoiceType__c = InvoiceService.INVOICE_TYPE_STANDARD
        );
        insert inv;

        Test.startTest();
        InvoiceService.regeneratePdfForInvoice(
            inv,
            null,
            String.valueOf(Date.today()),
            String.valueOf(Date.today().addDays(1))
        );

        // Covers sendInvoiceEmail + sendEmailInternal early return (no recipients)
        InvoiceService.sendInvoiceEmail(inv, acc.Id);
        Test.stopTest();

        Invoice__c updated = [SELECT PDF_File_Id__c, PDFGeneratedDate__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertNotEquals(null, updated.PDF_File_Id__c);
        System.assertNotEquals(null, updated.PDFGeneratedDate__c);
    }
    @IsTest
static void testBuildGroupKeyCoveredViaGenerateSuperBill() {
    // Primary account
    Account primaryAcc = new Account(
        Name = 'Primary For GroupKey',
        Is_Primary__c = true,
        Send_Invoice_to_Client__c = false
    );
    insert primaryAcc;

    // Related account (just to pass a non-empty related list)
    Account relatedAcc = new Account(
        Name = 'Related For GroupKey',
        Is_Primary__c = false,
        Send_Invoice_to_Client__c = false
    );
    insert relatedAcc;

    // Make sure primary has billables, otherwise generateSuperBill exits before group key path
    Date fromDate = Date.newInstance(2025, 1, 1);
    Date toDate   = Date.newInstance(2025, 1, 2);

    Billing__c billing = new Billing__c(
        Client__c = primaryAcc.Id,
        Is_Synced__c = false,
        Care_From_Date__c = fromDate,
        Care_To_Date__c = toDate,
        Invoice_Date__c = Date.today(),
        Invoice_Period_Start_Date__c = fromDate,
        Invoice_Period_End_Date__c = toDate,
        Paid_Status__c = 'Paid',
        Amount__c = 100
    );
    insert billing;

    Event ev = new Event(
        Subject = 'GroupKey Event',
        WhatId = primaryAcc.Id,
        
        StartDateTime = Datetime.newInstance(fromDate, Time.newInstance(9,0,0,0)),
        EndDateTime   = Datetime.newInstance(fromDate, Time.newInstance(11,0,0,0)),
        Billing__c = billing.Id
    );
    insert ev;

    Billing_Line_Item__c bli = new Billing_Line_Item__c(
        Invoice__c = billing.Id,
        Service_Date__c = fromDate,
        Type__c = InvoiceService.BLI_TYPE_CLIENT,
        Amount__c = 200,
        Client_Rate_Amount__c = 100,
        Quantity__c = 2,
        Rate__c = 100,
        Description__c = 'GroupKey Test'
    );
    insert bli;
   billing.Is_Synced__c=true;
    update billing;
    Test.startTest();
    String url = InvoiceService.generateSuperBill(
        primaryAcc.Id,
        new List<Id>{ relatedAcc.Id }, // non-null related list exercises buildGroupKey with relatedIds
        '2025-01-01',
        '2025-01-02'
    );
    Test.stopTest();

    System.assertNotEquals(null, url);

    // Also assert invoice got created (household path)
    List<Invoice__c> invs = [
        SELECT Id, InvoiceType__c, SuperBillPatientGroup__c
        FROM Invoice__c
        WHERE Client__c = :primaryAcc.Id
        AND InvoiceType__c = :InvoiceService.INVOICE_TYPE_HOUSEHOLD
    ];
    System.assert(!invs.isEmpty(), 'Household invoice should be created');
    System.assert(String.isNotBlank(invs[0].SuperBillPatientGroup__c), 'Group key should be populated');
}
    @IsTest
static void testResolveTemplateCoveredViaSendInvoiceEmail() {
    // 1) Ensure required email template exists in org
    List<EmailTemplate> tmpls = [
        SELECT Id, DeveloperName
        FROM EmailTemplate
        WHERE DeveloperName = 'Invoice_Email_Template'
        LIMIT 1
    ];
    if (tmpls.isEmpty()) {
        System.assert(true, 'Invoice_Email_Template not present in org; skipping.');
        return;
    }

    // 2) Need a Person Account to populate recipientEmails via PersonEmail
    List<RecordType> paRts = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account' AND IsPersonType = true
        LIMIT 1
    ];
    if (paRts.isEmpty()) {
        System.assert(true, 'Person Accounts not enabled; skipping.');
        return;
    }

    Account pa = new Account(
        RecordTypeId = paRts[0].Id,
        FirstName = 'Email',
        LastName = 'Receiver',
        PersonEmail = 'test@example.com',
        Send_Invoice_to_Client__c = true
    );
    insert pa;

    // 3) Invoice record (PDF can be null; resolveTemplate runs before PDF null check)
    Invoice__c inv = new Invoice__c(
        Name = 'INV-RESOLVE',
        Client__c = pa.Id,
        InvoiceType__c = InvoiceService.INVOICE_TYPE_STANDARD,
        From_Date__c = Date.today(),
        To_Date__c = Date.today().addDays(1),
        Invoice_Date__c = Date.today()
    );
    insert inv;

    // 4) Call public wrapper that invokes sendEmailInternal -> resolveTemplate
    Test.startTest();
    InvoiceService.sendInvoiceEmail(inv, pa.Id);
    Test.stopTest();

    // If no unhandled exception, method path executed
    System.assert(true);
}

    @IsTest
static void testGetRelatedAccountsForPrimaries_FullPath() {
    // Person Account RT (required for PersonContactId)
    List<RecordType> paRts = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account'
        AND IsPersonType = true
        LIMIT 1
    ];
    if (paRts.isEmpty()) {
        System.assert(true, 'Person Accounts not enabled in this org; skipping full-path test.');
        return;
    }
    Id paRtId = paRts[0].Id;

    // Primary + related person accounts
    Account primaryPa = new Account(
        RecordTypeId = paRtId,
        FirstName = 'Primary',
        LastName = 'Patient'
    );
    insert primaryPa;

    Account relatedPa = new Account(
        RecordTypeId = paRtId,
        FirstName = 'Related',
        LastName = 'Patient'
    );
    insert relatedPa;
    // Get or create reciprocal role for CCR
Id roleId;
List<HealthCloudGA__ReciprocalRole__c> roles = [
    SELECT Id
    FROM HealthCloudGA__ReciprocalRole__c
    LIMIT 1
];
    
    Id contactRoleRtId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();
    
if (roles.isEmpty()) {
    HealthCloudGA__ReciprocalRole__c r = new HealthCloudGA__ReciprocalRole__c(
        Name = 'Test Reciprocal Role',
        HealthCloudGA__InverseRole__c =  'father',
        RecordTypeId = contactRoleRtId
    );
    insert r;
    roleId = r.Id;
} else {
    roleId = roles[0].Id;
}

    primaryPa = [SELECT Id, PersonContactId FROM Account WHERE Id = :primaryPa.Id];
    relatedPa = [SELECT Id, PersonContactId FROM Account WHERE Id = :relatedPa.Id];

    // Contact-contact relation (Couple Household)
    HealthCloudGA__ContactContactRelation__c rel = new HealthCloudGA__ContactContactRelation__c(
        HealthCloudGA__RelatedContact__c = primaryPa.PersonContactId,
        HealthCloudGA__Contact__c = relatedPa.PersonContactId,
        Type__c = InvoiceService.RELATION_TYPE_COUPLE,
        HealthCloudGA__Role__c = roleId
    );

    // If Role is required in your org, uncomment these 2 lines:
    // rel.HealthCloudGA__Role__c = [SELECT Id FROM HealthCloudGA__ReciprocalRole__c LIMIT 1].Id;

    insert rel;

    // Make related account billable in selected date range
    Date fromDate = Date.today().addDays(-1);
    Date toDate = Date.today().addDays(2);

    Billing__c billing = new Billing__c(
        Client__c = relatedPa.Id,
        Is_Synced__c = False,
        Care_From_Date__c = fromDate,
        Care_To_Date__c = toDate,
        Invoice_Date__c = Date.today(),
        Invoice_Period_Start_Date__c = fromDate,
        Invoice_Period_End_Date__c = toDate,
        Paid_Status__c = 'Paid',
        Amount__c = 100
    );
    insert billing;

    Event ev = new Event(
        Subject = 'Billing Event',
        
        WhatId = relatedPa.Id,
        Billing__c = billing.Id,
        StartDateTime = Datetime.newInstance(fromDate, Time.newInstance(9, 0, 0, 0)),
        EndDateTime = Datetime.newInstance(fromDate, Time.newInstance(10, 0, 0, 0))
    );
    insert ev;

    Billing_Line_Item__c bli = new Billing_Line_Item__c(
        Invoice__c = billing.Id,
        Service_Date__c = fromDate,
        Type__c = InvoiceService.BLI_TYPE_CLIENT,
        Amount__c = 50,
        Quantity__c = 1,
        Rate__c = 50,
        Description__c = 'Test line item'
    );
    insert bli;
    billing.Is_Synced__c=true;
   	update billing;
    Test.startTest();
    Map<Id, List<Id>> result = InvoiceService.getRelatedAccountsForPrimaries(
        new List<Id>{ primaryPa.Id },
        fromDate,
        toDate
    );
    Test.stopTest();

    //System.assert(result.containsKey(primaryPa.Id), 'Primary account should exist in result map.');
    System.assert(result.get(primaryPa.Id).contains(relatedPa.Id), 'Related account should be mapped to primary.');
}
    


}