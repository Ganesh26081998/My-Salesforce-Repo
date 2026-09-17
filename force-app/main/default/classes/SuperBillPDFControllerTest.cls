@IsTest
private class SuperBillPDFControllerTest {

    private static Account createPersonAccount(String lastName) {
        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = prospectRtId,
            LastName = lastName,
            Address_Prospect__c = '123 Main Street Dallas TX 75001'
        );
        insert acc;
        return acc;
    }

    private static Id insertContactRole(String name, String inverse) {
        Id rtId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();
        HealthCloudGA__ReciprocalRole__c role = new HealthCloudGA__ReciprocalRole__c(
            Name = name,
            RecordTypeId = rtId,
            HealthCloudGA__InverseRole__c = inverse
        );
        insert role;
        return role.Id;
    }

    private static void createCCR(Id relatedContactId, Id contactId) {
        Id roleId = insertContactRole('Son', 'Father');
        insert new HealthCloudGA__ContactContactRelation__c(
            HealthCloudGA__RelatedContact__c = relatedContactId,
            HealthCloudGA__Contact__c = contactId,
            Type__c = 'Couple Household',
            HealthCloudGA__Role__c = roleId
        );
    }

    private static void createCCRWithRole(
        Id relatedContactId,
        Id contactId,
        Id roleId
    ) {
        insert new HealthCloudGA__ContactContactRelation__c(
            HealthCloudGA__RelatedContact__c = relatedContactId,
            HealthCloudGA__Contact__c = contactId,
            Type__c = 'Couple Household',
            HealthCloudGA__Role__c = roleId
        );
    }

    private static Billing__c insertBilling(Id accountId, Decimal amount) {
        Billing__c b = new Billing__c(
            Client__c = accountId,
            Is_Synced__c = false,
            Amount__c = amount,
            Care_From_Date__c = Date.today().addDays(-1),
            Care_To_Date__c = Date.today().addDays(-1),
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = Date.today().addDays(-1),
            Invoice_Period_End_Date__c = Date.today().addDays(-1),
            Paid_Status__c = 'Unpaid',
            Event_End_Date_Time__c = Datetime.newInstance(2026, 7, 8, 5, 0, 0),
            Event_Start_Date_Time__c = Datetime.newInstance(2026, 7, 9, 5, 0, 0)
        );
        insert b;
        return b;
    }

    /*private static void insertEvent(Id billingId, Integer hours) {
        insert new Event(
            Subject = 'Test Event',
            StartDateTime = Datetime.now().addDays(-1),
            EndDateTime = Datetime.now().addDays(-1).addHours(hours)            
        );
    }*/
private static void insertEvent(Id billingId, Integer hours) {
    Billing__c b = [SELECT Id, Client__c FROM Billing__c WHERE Id = :billingId LIMIT 1];
    insert new Event(
        Subject       = 'Test Event',
        WhatId        = b.Client__c,
        Billing__c    = billingId,
        StartDateTime = Datetime.now().addDays(-1),
        EndDateTime   = Datetime.now().addDays(-1).addHours(hours)
    );
}

    private static void setPageParams(
        String primaryAccountId,
        String relatedAccountIds,
        String fromDate,
        String toDate,
        String invoiceId
    ) {
        Test.setCurrentPage(Page.HouseholdInvoice);
        ApexPages.currentPage().getParameters().put('primaryAccountId', primaryAccountId);
        if (relatedAccountIds != null) {
            ApexPages.currentPage().getParameters().put('relatedAccountIds', relatedAccountIds);
        }
        ApexPages.currentPage().getParameters().put('fromDate', fromDate);
        ApexPages.currentPage().getParameters().put('toDate', toDate);
        if (invoiceId != null) {
            ApexPages.currentPage().getParameters().put('invoiceId', invoiceId);
        }
    }

    // -------------------------------------------------------------------------
    // helper — builds a CareDetailRow using the real 11-arg constructor
    // -------------------------------------------------------------------------
    private static BillingPDFUtility.CareDetailRow makeRow(
        String billingName,
        String bliName,
        String quantity,
        String rate,
        String amount,
        String description
    ) {
        return new BillingPDFUtility.CareDetailRow(
            billingName,   // billingName
            bliName,       // billingLineItemName
            Date.today(),  // serviceDate
            quantity,      // quantity
            rate,          // rate
            amount,        // amount
            description,   // description
            false,         // isHourly
            false,         // isExpenseOrMileage
            0,             // billingRowSpan
            0              // bliRowSpan
        );
    }

    // =========================================================================
    // EXISTING TESTS
    // =========================================================================
	
    @isTest
    static void testConstructorCoverage() {
        Account primaryAcc = createPersonAccount('Primary Account');
        Account relatedAcc  = createPersonAccount('Related Account');
        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id, PersonContactId FROM Account
            WHERE Id IN :new List<Id>{ primaryAcc.Id, relatedAcc.Id }
        ]);
        createCCR(
            accMap.get(primaryAcc.Id).PersonContactId,
            accMap.get(relatedAcc.Id).PersonContactId
        );
        // Add billing data for primary so constructor doesn't return early
        Billing__c b = insertBilling(primaryAcc.Id, 100);
        b.Is_Synced__c = true;
        update b;
        insertEvent(b.Id, 2);
        insert new Billing_Line_Item__c(
            Invoice__c = b.Id,
            Service_Date__c = Date.today().addDays(-1),
            Type__c = 'Client Billable',
            Client_Rate_Amount__c = 50,
            Quantity__c = 2,
            Amount__c = 100,
            Description__c = 'Test session'
        );
        setPageParams(
            primaryAcc.Id,
            relatedAcc.Id,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            'INV-1001'
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals('INV-1001', ctrl.invoiceNo);
        System.assertEquals('Primary Account', ctrl.clientName);
        System.assertNotEquals(null, ctrl.addressLines);
        System.assert(ctrl.patientSections.size() > 0);
    }

    @IsTest
    static void testInvalidParamsCoverage() {
        Test.setCurrentPage(Page.HouseholdInvoice);
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals(null, ctrl.clientName);
    }

    @IsTest
    static void testInvalidDateCoverage() {
        Account acc = createPersonAccount('Date Test');
        setPageParams(acc.Id, null, 'invalid-date', 'invalid-date', null);
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals(null, ctrl.clientName);
    }

    @IsTest
    static void testDeletedPrimaryAccountCoverage() {
        Account acc = createPersonAccount('Deleted Primary');
        Id deletedId = acc.Id;
        delete acc;
        setPageParams(
            deletedId, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals(null, ctrl.clientName);
        System.assertEquals(0, ctrl.patientSections.size());
    }

    @IsTest
    static void testUnrelatedAccountSkippedCoverage() {
        Account primaryAcc   = createPersonAccount('Primary Skip');
        Account unrelatedAcc = createPersonAccount('Unrelated Skip');
        Billing__c b = insertBilling(primaryAcc.Id, 100);
    b.Is_Synced__c = true;
    update b;
    insertEvent(b.Id, 2);
    insert new Billing_Line_Item__c(
        Invoice__c = b.Id,
        Service_Date__c = Date.today().addDays(-1),
        Type__c = 'Client Billable',
        Client_Rate_Amount__c = 50,
        Quantity__c = 2,
        Amount__c = 100,
        Description__c = 'Test session'
    );
        setPageParams(
            primaryAcc.Id,
            unrelatedAcc.Id,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals(1, ctrl.patientSections.size(),
            'Unrelated account should be skipped');
    }

    @IsTest
    static void testPublicAccessorsCoverage() {
        Test.setCurrentPage(Page.HouseholdInvoice);
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        ctrl.companyAddress   = 'Test Address';
        ctrl.primaryContact   = new Contact(LastName = 'PrimaryC');
        ctrl.relatedContact   = new Contact(LastName = 'RelatedC');
        ctrl.primaryContactId = 'pid';
        ctrl.relatedContactId = 'rid';
        Test.stopTest();
        System.assertEquals('Test Address', ctrl.companyAddress);
        System.assertEquals('PrimaryC',     ctrl.primaryContact.LastName);
        System.assertEquals('RelatedC',     ctrl.relatedContact.LastName);
        System.assertEquals('pid',          ctrl.primaryContactId);
        System.assertEquals('rid',          ctrl.relatedContactId);
    }

    @IsTest
    static void testAddressWrapCoverage() {
        Account acc = createPersonAccount('Wrap Test');
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        ctrl.prepareAddressLines();
        Test.stopTest();
        System.assert(ctrl.addressLines.size() > 0);
    }

    @IsTest
    static void testBlankAddressCoverage() {
        Account acc = createPersonAccount('Blank Address');
        acc.Address_Prospect__c = null;
        update acc;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        ctrl.prepareAddressLines();
        Test.stopTest();
        System.assertNotEquals(null, ctrl.addressLines);
    }

    @IsTest
    static void testWrapTextLongWordOverflowCoverage() {
        Account acc = createPersonAccount('Long Word Test');
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        ctrl.clientAddress =
            'Averylongstreetnamethatexceedsthirtycharseasily Houston TX 77001';
        ctrl.prepareAddressLines();
        Test.stopTest();
        System.assert(ctrl.addressLines.size() >= 1);
    }    

    @IsTest
    static void testEmptyRowsCoverage() {
        Account acc = createPersonAccount('Empty Rows Test');
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertNotEquals(null, ctrl.patientSections);
        System.assertEquals(0, ctrl.grandTotal);
    }

    @IsTest
    static void testPaymentDescAndDateFieldsCoverage() {
        Account acc = createPersonAccount('Payment Desc Test');
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            'INV-9999'
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals('Payment received on ', ctrl.paymentDesc);
        System.assertNotEquals(null, ctrl.invoiceDate);
        System.assertNotEquals(null, ctrl.fromDateStr);
        System.assertNotEquals(null, ctrl.toDateStr);
        System.assertEquals(10, ctrl.invoiceDate.length());
        System.assertEquals('INV-9999', ctrl.invoiceNo);
    }

    @IsTest
    static void testRelatedIdsBlankStringCoverage() {
        Account acc = createPersonAccount('Blank Related Ids');
        Billing__c b = insertBilling(acc.Id, 100);
    b.Is_Synced__c = true;
    update b;
    insertEvent(b.Id, 2);
    insert new Billing_Line_Item__c(
        Invoice__c = b.Id,
        Service_Date__c = Date.today().addDays(-1),
        Type__c = 'Client Billable',
        Client_Rate_Amount__c = 50,
        Quantity__c = 2,
        Amount__c = 100,
        Description__c = 'Test session'
    );
        setPageParams(
            acc.Id, '',
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals(1, ctrl.patientSections.size(),
            'Only primary section when relatedAccountIds is blank');
    }

    @IsTest
    static void testMultipleRelatedAccountsMixedCoverage() {
        Account primaryAcc  = createPersonAccount('Multi Primary');
        Account linkedAcc   = createPersonAccount('Multi Linked');
        Account unlinkedAcc = createPersonAccount('Multi Unlinked');
        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id, PersonContactId FROM Account
            WHERE Id IN :new List<Id>{ primaryAcc.Id, linkedAcc.Id }
        ]);
        createCCR(
            accMap.get(primaryAcc.Id).PersonContactId,
            accMap.get(linkedAcc.Id).PersonContactId
        );
        Billing__c b1 = insertBilling(primaryAcc.Id, 100);
    b1.Is_Synced__c = true;
    update b1;
    insertEvent(b1.Id, 2);
    insert new Billing_Line_Item__c(
        Invoice__c = b1.Id,
        Service_Date__c = Date.today().addDays(-1),
        Type__c = 'Client Billable',
        Client_Rate_Amount__c = 50,
        Quantity__c = 2,
        Amount__c = 100,
        Description__c = 'Primary session'
    );
    Billing__c b2 = insertBilling(linkedAcc.Id, 80);
    b2.Is_Synced__c = true;
    update b2;
    insertEvent(b2.Id, 2);
    insert new Billing_Line_Item__c(
        Invoice__c = b2.Id,
        Service_Date__c = Date.today().addDays(-1),
        Type__c = 'Client Billable',
        Client_Rate_Amount__c = 40,
        Quantity__c = 2,
        Amount__c = 80,
        Description__c = 'Linked session'
    );

        setPageParams(
            primaryAcc.Id,
            linkedAcc.Id + ',' + unlinkedAcc.Id,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals(2, ctrl.patientSections.size(),
            'Primary plus one linked; unlinked skipped');
    }

    @IsTest
    static void testRelatedContactWithRoleCoverage() {
        Account primaryAcc = createPersonAccount('Role Primary');
        Account relatedAcc = createPersonAccount('Role Related');
        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id, PersonContactId FROM Account
            WHERE Id IN :new List<Id>{ primaryAcc.Id, relatedAcc.Id }
        ]);
        Id roleId = insertContactRole('Spouse', 'Spouse');
        createCCRWithRole(
            accMap.get(primaryAcc.Id).PersonContactId,
            accMap.get(relatedAcc.Id).PersonContactId,
            roleId
        );
         Billing__c b1 = insertBilling(primaryAcc.Id, 100);
    b1.Is_Synced__c = true;
    update b1;
    insertEvent(b1.Id, 2);
    insert new Billing_Line_Item__c(
        Invoice__c = b1.Id,
        Service_Date__c = Date.today().addDays(-1),
        Type__c = 'Client Billable',
        Client_Rate_Amount__c = 50,
        Quantity__c = 2,
        Amount__c = 100,
        Description__c = 'Primary session'
    );
    Billing__c b2 = insertBilling(relatedAcc.Id, 80);
    b2.Is_Synced__c = true;
    update b2;
    insertEvent(b2.Id, 2);
    insert new Billing_Line_Item__c(
        Invoice__c = b2.Id,
        Service_Date__c = Date.today().addDays(-1),
        Type__c = 'Client Billable',
        Client_Rate_Amount__c = 40,
        Quantity__c = 2,
        Amount__c = 80,
        Description__c = 'Related session'
    );
        setPageParams(
            primaryAcc.Id,
            relatedAcc.Id,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals(2, ctrl.patientSections.size());
        System.assertNotEquals(null, ctrl.patientSections[1].roleName);
    }

    @IsTest
    static void testHourlyBillingCoverage() {
        Account acc = createPersonAccount('Hourly Test');
        Billing__c billing = insertBilling(acc.Id, 100);
        billing.Is_Synced__c = true;
        update billing;
        insertEvent(billing.Id, 2);
        insert new Billing_Line_Item__c(
            Invoice__c = billing.Id,
            Service_Date__c = Date.today().addDays(-1),
            Type__c = 'Client Billable',
            Client_Rate_Amount__c = 50,
            Quantity__c = 2,
            Amount__c = 100,
            Description__c = 'Hourly session'
        );       
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-2)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assert(ctrl.totalHourlyCharges >= 0);        
        System.assertNotEquals(null, ctrl.hourlySummaryRows);
    }

    @IsTest
    static void testMileageBillingCoverage() {
        Account acc = createPersonAccount('Mileage Test');
        Billing__c billing = insertBilling(acc.Id, 25);
        insertEvent(billing.Id, 1);
        insert new Billing_Line_Item__c(
            Invoice__c = billing.Id,
            Service_Date__c = Date.today().addDays(-1),
            Type__c = 'Mileage',
            Amount__c = 25,
            Mileage_Description__c = 'Client visit mileage',
            Description__c = 'Mileage reimbursement'
        );
        billing.Is_Synced__c = true;
        update billing;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-2)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assert(ctrl.totalMileageCharges >= 0);
    }

    @IsTest
    static void testExpenseBillingCoverage() {
        Account acc = createPersonAccount('Expense Test');
        Billing__c billing = insertBilling(acc.Id, 15);
        insertEvent(billing.Id, 1);
        insert new Billing_Line_Item__c(
            Invoice__c = billing.Id,
            Service_Date__c = Date.today().addDays(-1),
            Type__c = 'Expense/Credit',
            Amount__c = 15,
            Expense_Description__c = 'Office supplies expense',
            Description__c = 'Expense reimbursement'
        );
        billing.Is_Synced__c = true;
        update billing;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-2)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assert(ctrl.totalExpenseCharges >= 0);
    }

    @IsTest
    static void testMileageAndExpenseCombinedCoverage() {
        Account acc = createPersonAccount('Combined Charges Test');
        Billing__c billing = insertBilling(acc.Id, 40);
        insertEvent(billing.Id, 1);
        insert new List<Billing_Line_Item__c>{
            new Billing_Line_Item__c(
                Invoice__c = billing.Id,
                Service_Date__c = Date.today().addDays(-1),
                Type__c = 'Mileage',
                Amount__c = 25,
                Mileage_Description__c = 'Round trip',
                Description__c = 'Mileage reimbursement'
            ),
            new Billing_Line_Item__c(
                Invoice__c = billing.Id,
                Service_Date__c = Date.today().addDays(-1),
                Type__c = 'Expense/Credit',
                Amount__c = 15,
                Expense_Description__c = 'Supplies',
                Description__c = 'Expense reimbursement'
            )
        };
        billing.Is_Synced__c = true;
        update billing;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-2)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assert(ctrl.totalMileageCharges >= 0);
        System.assert(ctrl.totalExpenseCharges >= 0);
        System.assert(ctrl.totalCharges >= 0);
    }

    @IsTest
    static void testMultipleBillingLinesSameDateCoverage() {
        Account acc = createPersonAccount('Multi BLI Same Date');
        Billing__c billing = insertBilling(acc.Id, 160);
        insertEvent(billing.Id, 2);
        insert new List<Billing_Line_Item__c>{
            new Billing_Line_Item__c(
                Invoice__c = billing.Id,
                Service_Date__c = Date.today().addDays(-1),
                Type__c = 'Client Billable',
                Client_Rate_Amount__c = 50,
                Quantity__c = 2,
                Amount__c = 100,
                Description__c = 'Session A'
            ),
            new Billing_Line_Item__c(
                Invoice__c = billing.Id,
                Service_Date__c = Date.today().addDays(-1),
                Type__c = 'Client Billable',
                Client_Rate_Amount__c = 60,
                Quantity__c = 1,
                Amount__c = 60,
                Description__c = 'Session B'
            )
        };
		billing.Is_Synced__c = true;
        update billing;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-2)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assert(ctrl.patientSections.size() > 0);
        System.assertNotEquals(null, ctrl.hourlySummaryRows);
    }

    @IsTest
    static void testBillingWithoutQuantityCoverage() {
        Account acc = createPersonAccount('No Quantity Test');
        Billing__c billing = insertBilling(acc.Id, 100);
        insertEvent(billing.Id, 2);
        insert new Billing_Line_Item__c(
            Invoice__c = billing.Id,
            Service_Date__c = Date.today().addDays(-1),
            Type__c = 'Client Billable',
            Client_Rate_Amount__c = 50,
            Rate__c = 50,
            Amount__c = 100,
            Description__c = 'Session without quantity'
        );
        billing.Is_Synced__c = true;
        update billing;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-2)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assert(ctrl.totalHourlyCharges >= 0);
    }

    @IsTest
    static void testZeroAmountBillingCoverage() {
        Account acc = createPersonAccount('Zero Amount Test');
        Billing__c billing = insertBilling(acc.Id, 0);
        billing.Is_Synced__c = true;
        update billing;
        insertEvent(billing.Id, 1);
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-2)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals(0, ctrl.patientSections.size());
        System.assertEquals(0, ctrl.grandTotal);
    }

    @IsTest
    static void testGrandTotalAcrossTwoSectionsCoverage() {
        Account primaryAcc = createPersonAccount('Grand Total Primary');
        Account relatedAcc = createPersonAccount('Grand Total Related');
        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id, PersonContactId FROM Account
            WHERE Id IN :new List<Id>{ primaryAcc.Id, relatedAcc.Id }
        ]);
        createCCR(
            accMap.get(primaryAcc.Id).PersonContactId,
            accMap.get(relatedAcc.Id).PersonContactId
        );
        Billing__c b1 = insertBilling(primaryAcc.Id, 50);
b1.Is_Synced__c = true;
update b1;
insertEvent(b1.Id, 1);
insert new Billing_Line_Item__c(
    Invoice__c = b1.Id,
    Service_Date__c = Date.today().addDays(-1),
    Type__c = 'Client Billable',
    Client_Rate_Amount__c = 50,
    Quantity__c = 1,
    Amount__c = 50,
    Description__c = 'Primary session'
);
Billing__c b2 = insertBilling(relatedAcc.Id, 50);
b2.Is_Synced__c = true;
update b2;
insertEvent(b2.Id, 1);
insert new Billing_Line_Item__c(
    Invoice__c = b2.Id,
    Service_Date__c = Date.today().addDays(-1),
    Type__c = 'Client Billable',
    Client_Rate_Amount__c = 50,
    Quantity__c = 1,
    Amount__c = 50,
    Description__c = 'Related session'
);
        setPageParams(
            primaryAcc.Id,
            relatedAcc.Id,
            String.valueOf(Date.today().addDays(-2)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertEquals(2, ctrl.patientSections.size());
        System.assert(ctrl.grandTotal >= 0);
    }

    @IsTest
    static void testAddressWithAllFieldsCoverage() {
        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = prospectRtId,
            LastName = 'Full Address Test',
            Address_Prospect__c = '456 Oak Avenue Austin TX 78701 USA'
        );
        insert acc;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertNotEquals(null, ctrl.clientName);
    }

    @IsTest
    static void testPartialAddressCoverage() {
        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = prospectRtId,
            LastName = 'Partial Address',
            Address_Prospect__c = 'Dallas TX'
        );
        insert acc;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertNotEquals(null, ctrl.clientName);
    }

    @IsTest
    static void testStatePostalOnlyCoverage() {
        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = prospectRtId,
            LastName = 'State Postal Only',
            Address_Prospect__c = 'TX 75001'
        );
        insert acc;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertNotEquals(null, ctrl.clientAddress);
    }

    @IsTest
    static void testCountryOnlyCoverage() {
        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = prospectRtId,
            LastName = 'Country Only',
            Address_Prospect__c = 'USA'
        );
        insert acc;
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );
        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();
        Test.stopTest();
        System.assertNotEquals(null, ctrl.clientAddress);
    }

    // =========================================================================
    // NEW TEST — applyBillingRowSpan all five branches
    // =========================================================================

    @IsTest
    static void testApplyBillingRowSpanAllBranchesCoverage() {

        Account acc = createPersonAccount('RowSpan Test');
        setPageParams(
            acc.Id, null,
            String.valueOf(Date.today().addDays(-7)),
            String.valueOf(Date.today()),
            null
        );

        Test.startTest();
        SuperBillPDFController ctrl = new SuperBillPDFController();

        // ---------------------------------------------------------------------
        // Branch 1: null list — early return, must not throw
        // ---------------------------------------------------------------------
        ctrl.applyBillingRowSpan(null);

        // ---------------------------------------------------------------------
        // Branch 2: empty list — early return, must not throw
        // ---------------------------------------------------------------------
        ctrl.applyBillingRowSpan(new List<BillingPDFUtility.CareDetailRow>());

        // ---------------------------------------------------------------------
        // Branch 3: first row of 'Provider A'  → showBillingName = true,  rowSpan = 2
        // Branch 4: second row of 'Provider A' → showBillingName = false  (else branch)
        // Branch 5: first row of 'Provider B'  → showBillingName = true,  rowSpan = 1
        // ---------------------------------------------------------------------
        BillingPDFUtility.CareDetailRow r1 = makeRow(
            'Provider A', 'BLI-001', '2 hrs', '50/hr', '$100.00', 'Morning session'
        );
        BillingPDFUtility.CareDetailRow r2 = makeRow(
            'Provider A', 'BLI-002', '1 hrs', '50/hr', '$50.00', 'Afternoon session'
        );
        BillingPDFUtility.CareDetailRow r3 = makeRow(
            'Provider B', 'BLI-003', '3 hrs', '60/hr', '$180.00', 'Evening session'
        );

        List<BillingPDFUtility.CareDetailRow> rows =
            new List<BillingPDFUtility.CareDetailRow>{ r1, r2, r3 };

        ctrl.applyBillingRowSpan(rows);

        Test.stopTest();

        // Provider A — first row
        System.assertEquals(
            true,
            rows[0].showBillingName,
            'First row of Provider A must show the billing name'
        );
        System.assertEquals(
            2,
            rows[0].billingRowSpan,
            'Provider A appears twice so rowSpan must be 2'
        );

        // Provider A — second row (else branch covered here)
        System.assertEquals(
            false,
            rows[1].showBillingName,
            'Second row of Provider A must NOT show the billing name'
        );

        // Provider B — only row in its group
        System.assertEquals(
            true,
            rows[2].showBillingName,
            'First row of Provider B must show the billing name'
        );
        System.assertEquals(
            1,
            rows[2].billingRowSpan,
            'Provider B appears once so rowSpan must be 1'
        );
    }
}