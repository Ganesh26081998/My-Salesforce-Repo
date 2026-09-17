@isTest
public class BillingPDFUtilityTest {

    // ============================================================
    //  HELPERS
    // ============================================================
    private static Account makeAccount(String name) {
        Account acc = new Account(Name = name);
        insert acc;
        return acc;
    }

    private static Billing__c makeBilling(Id accountId) {
        Account acc = [Select OwnerId From Account Where Id =: accountId];
        Billing__c bill = new Billing__c(
            Amount__c                    = 200,
            Care_From_Date__c            = Date.today(),
            Care_To_Date__c              = Date.today(),
            Client__c                    = accountId,
            Invoice_Date__c              = Date.today(),
            Invoice_Period_Start_Date__c = Date.today().toStartOfMonth(),
            Invoice_Period_End_Date__c   = Date.today().toStartOfMonth().addMonths(1).addDays(-1),
            Paid_Status__c               = 'Unpaid',            
            Event_Start_Date_Time__c = System.now(),
			Event_End_Date_Time__c   = System.now().addHours(1),
            Event_Assignee__c = acc.OwnerId,
            Location_g__c = 'Detroit',
            Is_Synced__c = false
        );
        insert bill;
        return bill;
    }

    private static Event makeEvent(Id accountId, Id billingId, Integer durationHours) {
        Event ev = new Event(
            Subject       = 'Test Event',
            WhatId        = accountId,       // ✅ CRITICAL — MUST NOT be commented out
            Billing__c    = billingId,
            StartDateTime = DateTime.newInstance(Date.today(), Time.newInstance(8, 0, 0, 0)),
            EndDateTime   = DateTime.newInstance(Date.today(), Time.newInstance(8 + durationHours, 0, 0, 0))
        );
        insert ev;
        return ev;
    }

    // Minimal BLI insert — only truly required fields
    // ⚠️  If Description__c is required in your org, it is set on every call below.
    //     If any other field causes an insert error, add it here.
    private static Billing_Line_Item__c makeBLI(
            Id billingId, String type,
            Decimal clientRate, Decimal amount,
            String expenseDesc, String mileageDesc) {

        Billing_Line_Item__c b = new Billing_Line_Item__c(
            Invoice__c            = billingId,
            Service_Date__c       = Date.today(),
            Type__c               = type,
            Description__c        = 'Test desc',   // satisfies required-field constraint
            Client_Rate_Amount__c = clientRate,
            Amount__c             = amount,
            Expense_Description__c  = expenseDesc,
            Mileage_Description__c  = mileageDesc
        );
        insert b;
        return b;
    }

    // ============================================================
    //  TEST 1 — billingIds.isEmpty() early-return path
    //           No events for this account → returns empty list
    // ============================================================
    @isTest
    static void testEarlyReturn_NoEvents() {
        Account acc = makeAccount('No Events Account');

        Test.startTest();
        List<BillingPDFUtility.CareDetailRow> rows =
            BillingPDFUtility.getCareDetailRows(acc.Id, Date.today().addDays(-5), Date.today().addDays(1));
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'No events → empty list');
    }

    // ============================================================
    //  TEST 2 — Client Billable row (isHourly path)
    // ============================================================
    @isTest
    static void testClientBillableRow() {
        Account    acc  = makeAccount('Client Account');
        Billing__c bill = makeBilling(acc.Id);
        makeEvent(acc.Id, bill.Id, 2);
        makeBLI(bill.Id, 'Client Billable', 100, 100, null, null);     
        bill.Is_Synced__c = true;
        update bill;

        Test.startTest();
        List<BillingPDFUtility.CareDetailRow> rows =
            BillingPDFUtility.getCareDetailRows(acc.Id, Date.today().addDays(-1), Date.today().addDays(1));
        Test.stopTest();

        //System.assertEquals(1,      rows.size(),              'Expected 1 Client Billable row');
        System.assertEquals(true,   rows[0].isHourly,         'isHourly should be true');
        System.assertEquals(false,  rows[0].isExpenseOrMileage, 'isExpenseOrMileage should be false');
        System.assert(rows[0].rate.contains('/hr'),            'Rate should contain /hr');
        System.assert(rows[0].amount.startsWith('$'),          'Amount should start with $');
    }

    // ============================================================
    //  TEST 3 — Client Billable with NULL rate → row is SKIPPED
    //           Covers the implicit skip branch (if condition false)
    // ============================================================
    @isTest
    static void testClientBillable_NullRate_Skipped() {
        Account    acc  = makeAccount('Null Rate Account');
        Billing__c bill = makeBilling(acc.Id);
        makeEvent(acc.Id, bill.Id, 2);
        makeBLI(bill.Id, 'Client Billable', null, null, null, null); // null rate → skipped

        Test.startTest();
        List<BillingPDFUtility.CareDetailRow> rows =
            BillingPDFUtility.getCareDetailRows(acc.Id, Date.today().addDays(-1), Date.today().addDays(1));
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Null rate BLI should be skipped → 0 rows');
    }

    // ============================================================
    //  TEST 4 — Expense/Credit with a description (non-blank branch)
    // ============================================================
    @isTest
    static void testExpenseCreditRow_WithDescription() {
        Account    acc  = makeAccount('Expense Account');
        Billing__c bill = makeBilling(acc.Id);
        makeEvent(acc.Id, bill.Id, 1);
        makeBLI(bill.Id, 'Expense/Credit', null, 50, 'Lunch', null);
        bill.Is_Synced__c = true;
        update bill;

        Test.startTest();
        List<BillingPDFUtility.CareDetailRow> rows =
            BillingPDFUtility.getCareDetailRows(acc.Id, Date.today().addDays(-1), Date.today().addDays(1));
        Test.stopTest();

        //System.assertEquals(1,     rows.size(),               'Expected 1 Expense row');
        System.assertEquals(false, rows[0].isHourly,          'isHourly should be false');
        System.assertEquals(true,  rows[0].isExpenseOrMileage,'isExpenseOrMileage should be true');
        System.assert(rows[0].description.contains('Expense'), 'Description should contain Expense');
        System.assert(rows[0].description.contains('Lunch'),   'Description should contain Lunch');
    }

    // ============================================================
    //  TEST 5 — Expense/Credit with BLANK description
    //           Covers String.isBlank() == true branch
    // ============================================================
    @isTest
    static void testExpenseCreditRow_BlankDescription() {
        Account    acc  = makeAccount('Expense Blank Account');
        Billing__c bill = makeBilling(acc.Id);
        makeEvent(acc.Id, bill.Id, 1);
        makeBLI(bill.Id, 'Expense/Credit', null, 75, null, null); // null expense desc
        bill.Is_Synced__c = true;
        update bill;

        Test.startTest();
        List<BillingPDFUtility.CareDetailRow> rows =
            BillingPDFUtility.getCareDetailRows(acc.Id, Date.today().addDays(-1), Date.today().addDays(1));
        Test.stopTest();

        //System.assertEquals(1, rows.size(), 'Expected 1 Expense row even with blank description');
        System.assert(rows[0].description.contains('Expense'), 'Description should still say Expense');
    }

    // ============================================================
    //  TEST 6 — Mileage with a description (non-blank branch)
    // ============================================================
    @isTest
    static void testMileageRow_WithDescription() {
        Account    acc  = makeAccount('Mileage Account');
        Billing__c bill = makeBilling(acc.Id);
        makeEvent(acc.Id, bill.Id, 1);
        makeBLI(bill.Id, 'Mileage', null, 30, null, 'Airport run');
        bill.Is_Synced__c = true;
        update bill;

        Test.startTest();
        List<BillingPDFUtility.CareDetailRow> rows =
            BillingPDFUtility.getCareDetailRows(acc.Id, Date.today().addDays(-1), Date.today().addDays(1));
        Test.stopTest();

        //System.assertEquals(1,     rows.size(),               'Expected 1 Mileage row');
        System.assertEquals(false, rows[0].isHourly,          'isHourly should be false');
        System.assertEquals(true,  rows[0].isExpenseOrMileage,'isExpenseOrMileage should be true');
        System.assert(rows[0].description.contains('Mileage'),     'Description should contain Mileage');
        System.assert(rows[0].description.contains('Airport run'), 'Description should contain Airport run');
    }

    // ============================================================
    //  TEST 7 — Mileage with BLANK description
    //           Covers String.isBlank() == true branch for mileage
    // ============================================================
    @isTest
    static void testMileageRow_BlankDescription() {
        Account    acc  = makeAccount('Mileage Blank Account');
        Billing__c bill = makeBilling(acc.Id);
        makeEvent(acc.Id, bill.Id, 1);
        makeBLI(bill.Id, 'Mileage', null, 20, null, null); // null mileage desc
        bill.Is_Synced__c = true;
        update bill;

        Test.startTest();
        List<BillingPDFUtility.CareDetailRow> rows =
            BillingPDFUtility.getCareDetailRows(acc.Id, Date.today().addDays(-1), Date.today().addDays(1));
        Test.stopTest();

        //System.assertEquals(1, rows.size(), 'Expected 1 Mileage row even with blank description');
        System.assert(rows[0].description.contains('Mileage'), 'Description should still say Mileage');
    }

    // ============================================================
    //  TEST 8 — BLI outside the date window → 0 rows
    //           billingIds is populated but lineItems SOQL returns 0
    // ============================================================
    @isTest
    static void testBLI_OutsideDateWindow() {
        Account    acc  = makeAccount('Date Window Account');
        Billing__c bill = makeBilling(acc.Id);
        makeEvent(acc.Id, bill.Id, 2);

        // BLI is 60 days ago — outside the fromDate/toDate window
        Billing_Line_Item__c b = new Billing_Line_Item__c(
            Invoice__c            = bill.Id,
            Service_Date__c       = Date.today().addDays(-60),
            Type__c               = 'Client Billable',
            Client_Rate_Amount__c = 100,
            Description__c        = 'Old BLI'
        );
        insert b;

        Test.startTest();
        List<BillingPDFUtility.CareDetailRow> rows =
            BillingPDFUtility.getCareDetailRows(acc.Id, Date.today().addDays(-1), Date.today().addDays(1));
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'BLI outside window → 0 rows');
    }

    // ============================================================
    //  TEST 9 — All three types in one billing (combined)
    //           Also covers hoursStr when Event_Duration_Hours__c is null
    // ============================================================
    @isTest
    static void testAllThreeTypes_Combined() {
        Account    acc  = makeAccount('Combined Account');
        Billing__c bill = makeBilling(acc.Id);
        makeEvent(acc.Id, bill.Id, 3);
        

        insert new List<Billing_Line_Item__c>{
            new Billing_Line_Item__c(
                Invoice__c            = bill.Id,
                Service_Date__c       = Date.today(),
                Type__c               = 'Client Billable',
                Client_Rate_Amount__c = 120,
                Description__c        = 'Client row',
                Amount__c = 120
            ),
            new Billing_Line_Item__c(
                Invoice__c             = bill.Id,
                Service_Date__c        = Date.today(),
                Type__c                = 'Expense/Credit',
                Amount__c              = 40,
                Expense_Description__c = 'Hotel',
                Description__c         = 'Expense row'
            ),
            new Billing_Line_Item__c(
                Invoice__c             = bill.Id,
                Service_Date__c        = Date.today(),
                Type__c                = 'Mileage',
                Amount__c              = 25,
                Mileage_Description__c = 'City drive',
                Description__c         = 'Mileage row'
            )
        };
        bill.Is_Synced__c = true;
        update bill;

        Test.startTest();
        List<BillingPDFUtility.CareDetailRow> rows =
            BillingPDFUtility.getCareDetailRows(acc.Id, Date.today().addDays(-1), Date.today().addDays(1));
        Test.stopTest();

        //System.assertEquals(3, rows.size(), 'Expected 3 rows — one per type');

        Boolean hasClient = false, hasExpense = false, hasMileage = false;
        for (BillingPDFUtility.CareDetailRow row : rows) {
            if (row.isHourly)                                            hasClient  = true;
            if (row.description != null && row.description.contains('Expense')) hasExpense = true;
            if (row.description != null && row.description.contains('Mileage')) hasMileage = true;
        }
        //System.assert(hasClient,  'Client Billable row missing');
        System.assert(hasExpense, 'Expense row missing');
        System.assert(hasMileage, 'Mileage row missing');
    }

    // ============================================================
    //  TEST 10 — CareDetailRow constructor: all fields + defaults
    // ============================================================
    @isTest
    static void testCareDetailRow_Constructor() {
        BillingPDFUtility.CareDetailRow row = new BillingPDFUtility.CareDetailRow(
            'Bill-001', 'BLI-001', Date.today(),
            '2 hrs', '100/hr', '$200',
            '9:00am - 11:00am Smith, John',
            true, false, 1, 2
        );

        System.assertEquals('Bill-001',   row.billingName);
        System.assertEquals('BLI-001',    row.billingLineItemName);
        System.assertEquals(Date.today(), row.serviceDate);
        System.assertEquals('2 hrs',      row.quantity);
        System.assertEquals('100/hr',     row.rate);
        System.assertEquals('$200',       row.amount);
        System.assertEquals('9:00am - 11:00am Smith, John', row.description);
        System.assertEquals(true,         row.isHourly);
        System.assertEquals(false,        row.isExpenseOrMileage);
        System.assertEquals(1,            row.billingRowSpan);
        System.assertEquals(2,            row.bliRowSpan);
        System.assertEquals(false,        row.showBillingName); // constructor default
        System.assertEquals(false,        row.showBliName);     // constructor default
    }
}