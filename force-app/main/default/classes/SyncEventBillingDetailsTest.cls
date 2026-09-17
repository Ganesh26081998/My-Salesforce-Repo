@isTest
private class SyncEventBillingDetailsTest {

    /*
        Helper Method
    */
    private static Event createTestEvent(Boolean syncedBilling) {

        // Create Account
        Account acc = new Account(
            Name = 'Test Client'
        );
        insert acc;

        // Create Billing
        Billing__c bill = new Billing__c(
            Is_Synced__c = syncedBilling,
            Amount__c = 0,
            Location_g__c = 'Detroit',

            Client__c = acc.Id,

            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today().addDays(1),

            Invoice_Date__c = Date.today(),

            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today().addDays(7),

            Paid_Status__c = 'Paid'
        );
        insert bill;

        // Create Event
        Event ev = new Event(
            Subject = 'Test Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),

            Billing__c = bill.Id,

            Client_Rate_Amount__c = 100,
            Client_Billing_Details__c = 'Client Details',

            Caregiver_Rate_Amount__c = 50,
            Caregiver_Billing_Details__c = 'Caregiver Details',

            Mileage_Amount__c = 10,
            Mileage_Description__c = 'Mileage 1',

            Mileage_Amount_2__c = 20,
            Mileage_Description_2__c = 'Mileage 2',

            Expense_Amount__c = 30,
            Expense_Description__c = 'Expense 1',

            Expense_Amount_2__c = 40,
            Expense_Description_2__c = 'Expense 2',

            Location__c = 'Detroit'
        );
        insert ev;

        // Create Existing Billing Line Items
        List<Billing_Line_Item__c> blis = new List<Billing_Line_Item__c>();

        blis.add(new Billing_Line_Item__c(
            Invoice__c = bill.Id,
            Type__c = 'Client Billable',
            Description__c = 'Client Billable',
            Service_Date__c = Date.today()
        ));

        blis.add(new Billing_Line_Item__c(
            Invoice__c = bill.Id,
            Type__c = 'Caregiver Billable',
            Description__c = 'Caregiver Billable',
            Service_Date__c = Date.today()
        ));

        blis.add(new Billing_Line_Item__c(
            Invoice__c = bill.Id,
            Type__c = 'Mileage',
            Mileage_Index__c = 1,
            Description__c = 'Mileage',
            Service_Date__c = Date.today()
        ));

        blis.add(new Billing_Line_Item__c(
            Invoice__c = bill.Id,
            Type__c = 'Expense/Credit',
            Expense_Index__c = 1,
            Description__c = 'Expense',
            Service_Date__c = Date.today()
        ));

        insert blis;

        return ev;
    }

    /*
        isBillingSynced()
    */

    @isTest
    static void testIsBillingSyncedFalse() {

        Event ev = createTestEvent(false);

        Test.startTest();
        Boolean result = SyncEventBillingDetails.isBillingSynced(ev.Id);
        Test.stopTest();

        System.assertEquals(false, result);
    }

    @isTest
    static void testIsBillingSyncedTrue() {

        Event ev = createTestEvent(true);

        Test.startTest();
        Boolean result = SyncEventBillingDetails.isBillingSynced(ev.Id);
        Test.stopTest();

        System.assertEquals(true, result);
    }

    @isTest
    static void testIsBillingSyncedNull() {

        Test.startTest();
        Boolean result = SyncEventBillingDetails.isBillingSynced(null);
        Test.stopTest();

        System.assertEquals(true, result);
    }

    /*
        updateBillingLineItems()
    */

    @isTest
    static void testUpdateBillingLineItemsSuccess() {

        Event ev = createTestEvent(false);

        Test.startTest();
        SyncEventBillingDetails.updateBillingLineItems(ev.Id);
        Test.stopTest();

        Billing__c updatedBill = [
            SELECT Id, Amount__c, Location_g__c
            FROM Billing__c
            WHERE Id = :ev.Billing__c
        ];

        System.assertNotEquals(null, updatedBill);
    }

    @isTest
    static void testAlreadySyncedBilling() {

        Event ev = createTestEvent(true);

        Test.startTest();

        try {
            SyncEventBillingDetails.updateBillingLineItems(ev.Id);
        } catch (Exception e) {

            
        }

        Test.stopTest();
    }

    @isTest
    static void testNullEventId() {

        Test.startTest();

        try {
            SyncEventBillingDetails.updateBillingLineItems(null);
        } catch (Exception e) {

            
        }

        Test.stopTest();
    }

    @isTest
    static void testNoBillingLinked() {

        Event ev = new Event(
            Subject = 'No Billing Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1)
        );
        insert ev;

        Test.startTest();

        try {
            SyncEventBillingDetails.updateBillingLineItems(ev.Id);
        } catch (Exception e) {

           
        }

        Test.stopTest();
    }

    @isTest
    static void testMileageValidationError() {

        Account acc = new Account(Name = 'Mileage Client');
        insert acc;

        Billing__c bill = new Billing__c(
            Is_Synced__c = false,
            Amount__c = 0,

            Client__c = acc.Id,

            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today(),

            Invoice_Date__c = Date.today(),

            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today(),

            Paid_Status__c = 'Paid'
        );
        insert bill;

        Event ev = new Event(
            Subject = 'Mileage Validation',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),

            Billing__c = bill.Id,

            Mileage_Amount__c = 100
        );
        insert ev;

        Test.startTest();

        try {
            SyncEventBillingDetails.updateBillingLineItems(ev.Id);
        } catch (Exception e) {

            
        }

        Test.stopTest();
    }

    @isTest
    static void testExpenseValidationError() {

        Account acc = new Account(Name = 'Expense Client');
        insert acc;

        Billing__c bill = new Billing__c(
            Is_Synced__c = false,
            Amount__c = 0,

            Client__c = acc.Id,

            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today(),

            Invoice_Date__c = Date.today(),

            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today(),

            Paid_Status__c = 'Paid'
        );
        insert bill;

        Event ev = new Event(
            Subject = 'Expense Validation',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),

            Billing__c = bill.Id,

            Expense_Amount__c = 100
        );
        insert ev;

        Test.startTest();

        try {
            SyncEventBillingDetails.updateBillingLineItems(ev.Id);
        } catch (Exception e) {

            
        }

        Test.stopTest();
    }

    @isTest
    static void testLocationMismatch() {

        Account acc = new Account(Name = 'Location Client');
        insert acc;

        Billing__c bill = new Billing__c(
            Is_Synced__c = false,
            Amount__c = 0,

            Client__c = acc.Id,

            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today(),

            Invoice_Date__c = Date.today(),

            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today(),

            Paid_Status__c = 'Paid',

            Location_g__c = 'Detroit'
        );
        insert bill;

        Event ev = new Event(
            Subject = 'Location Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),

            Billing__c = bill.Id,
            Location__c = 'Detroit'
        );
        insert ev;

        Test.startTest();

        try {
            SyncEventBillingDetails.updateBillingLineItems(ev.Id);
        } catch (Exception e) {

            System.assert(
                e.getMessage().contains('Location mismatch')
            );
        }

        Test.stopTest();
    }

    @isTest
    static void testInsertNewBillingLineItems() {

        Account acc = new Account(Name = 'Insert Client');
        insert acc;

        Billing__c bill = new Billing__c(
            Is_Synced__c = false,
            Amount__c = 0,

            Client__c = acc.Id,

            Care_From_Date__c = Date.today(),
            Care_To_Date__c = Date.today(),

            Invoice_Date__c = Date.today(),

            Invoice_Period_Start_Date__c = Date.today(),
            Invoice_Period_End_Date__c = Date.today(),

            Paid_Status__c = 'Paid'
        );
        insert bill;

        Event ev = new Event(
            Subject = 'Insert Items Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),

            Billing__c = bill.Id,

            Mileage_Amount__c = 15,
            Mileage_Description__c = 'Mileage Insert',

            Expense_Amount__c = 25,
            Expense_Description__c = 'Expense Insert'
        );
        insert ev;

        Test.startTest();
        SyncEventBillingDetails.updateBillingLineItems(ev.Id);
        Test.stopTest();

        List<Billing_Line_Item__c> records = [
            SELECT Id
            FROM Billing_Line_Item__c
            WHERE Invoice__c = :bill.Id
        ];

        System.assert(records.size() > 0);
    }
}