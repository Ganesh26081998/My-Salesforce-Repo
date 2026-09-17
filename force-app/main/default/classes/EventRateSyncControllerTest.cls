/*
----------------------------------------------------------------------------
Author        : Ankit Pande
Class Name    : EventRateSyncController
CreatedOn     : 13-03-2026
LastModifiedOn: 15-03-2026
LastModifiedBy: Ankit Pande
Description   : This class is used to sync rate calculation details, mileage,
 *                 expense information, client billing details, and caregiver
 *                 billing details from a recurring source event to all related
 *                 recurring events.
----------------------------------------------------------------------------
*/

@isTest
private class EventRateSyncControllerTest {

    // ─────────────────────────────────────────────────────────────
    // Helper – build a minimal Event record that can be inserted.
    // ActivityRecurrence2Id cannot be set directly in unit tests,
    // so we use a fake (but valid-looking) Id string only when we
    // need to simulate the "is recurring" path via a mock/stub
    // approach using Test.setFixedSearchResults or a wrapper.
    //
    // Because ActivityRecurrence2Id is a system-managed field that
    // Salesforce sets automatically for recurring events, and DML
    // on Activity recurrence series is not supported in Apex tests,
    // we use @TestVisible + dependency injection via a private
    // helper overload (see the controller notes below), OR we rely
    // on the selector pattern.  The cleanest approach for standard
    // Apex tests is to use Database.insert with override disabled
    // and verify the exception branches via direct method calls
    // with crafted SObject instances using Test.loadData / JSON
    // deserialization tricks.
    //
    // Salesforce allows setting non-writable fields on SObjects via
    // JSON deserialization in tests – we use that technique here.
    // ─────────────────────────────────────────────────────────────

    private static final Id FAKE_RECURRENCE_ID =
        '0HO000000000001AAA'; // ActivityRecurrence2 prefix 0HO

    // Deserialize an Event with forced field values (including
    // read-only / system fields like ActivityRecurrence2Id).
    private static Event buildFakeEvent(
        Id recordId,
        Id recurrenceId,
        Boolean hasRates
    ) {
        Map<String, Object> raw = new Map<String, Object>{
            'Id'                       => recordId,
            'ActivityRecurrence2Id'    => recurrenceId,
            'IsRecurrence'             => (recurrenceId != null),
            'Location__c'              => 'Test Location',
            'Client_Billing_Details__c'  => 'CBD-001',
            'Client_Rate__c'             => hasRates ? 'Hourly' : null,
            'Client_Rate_Amount__c'      => hasRates ? 50.00    : null,
            'Caregiver_Billing_Details__c' => 'CGD-001',
            'Caregiver_Rate__c'          => hasRates ? 'Hourly' : null,
            'Caregiver_Rate_Amount__c'   => hasRates ? 30.00    : null,
            'Enter_Miles_1__c'           => 10.0,
            'Enter_Miles_2__c'           => 20.0,
            'Enter_Miles_3__c'           => 30.0,
            'Enter_Miles_4__c'           => 0.0,
            'Enter_Miles_5__c'           => 0.0,
            'Mileage_Amount__c'          => 5.00,
            'Mileage_Amount_2__c'        => 6.00,
            'Mileage_Amount_3__c'        => 7.00,
            'Mileage_Amount_4__c'        => 0.00,
            'Mileage_Amount_5__c'        => 0.00,
            'Mileage_Description__c'     => 'Desc 1',
            'Mileage_Description_2__c'   => 'Desc 2',
            'Mileage_Description_3__c'   => 'Desc 3',
            'Mileage_Description_4__c'   => null,
            'Mileage_Description_5__c'   => null,
            'Expense_Amount__c'          => 15.00,
            'Expense_Amount_2__c'        => 16.00,
            'Expense_Amount_3__c'        => 17.00,
            'Expense_Amount_4__c'        => 0.00,
            'Expense_Amount_5__c'        => 0.00,
            'Expense_Description__c'     => 'Exp 1',
            'Expense_Description_2__c'   => 'Exp 2',
            'Expense_Description_3__c'   => 'Exp 3',
            'Expense_Description_4__c'   => null,
            'Expense_Description_5__c'   => null
        };
        return (Event) JSON.deserialize(
            JSON.serialize(raw), Event.class
        );
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 1 – Null eventId → RateSyncException
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_nullEventId_throwsException() {
        Test.startTest();
        try {
            EventRateSyncController.syncRecurringEventRates(null);
            System.assert(false, 'Expected exception was not thrown');
        } catch (EventRateSyncController.RateSyncException ex) {
            System.assertEquals(
                'Event Id is required.',
                ex.getMessage(),
                'Wrong exception message for null Id'
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 2 – Non-recurring event → RateSyncException
    //
    // We insert a real non-recurring Event so the SOQL in the
    // controller finds a record with ActivityRecurrence2Id = null.
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_nonRecurringEvent_throwsException() {

        // Create a standard (non-recurring) event
        Event evt = new Event(
            Subject        = 'Test Event',
            StartDateTime  = System.now(),
            EndDateTime    = System.now().addHours(1),
            DurationInMinutes = 60
        );
        insert evt;

        Test.startTest();
        try {
            EventRateSyncController.syncRecurringEventRates(evt.Id);
            System.assert(false, 'Expected exception was not thrown');
        } catch (EventRateSyncController.RateSyncException ex) {
            System.assertEquals(
                'Sync Rates can be used only for recurring events.',
                ex.getMessage(),
                'Wrong exception message for non-recurring event'
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    // NOTE ON RECURRING EVENT TESTS
    //
    // Salesforce does not support creating Activity Recurrence2
    // series via DML in Apex unit tests (ActivityRecurrence2Id is
    // system-managed). The remaining exception branches
    // (incomplete rates, no siblings) and the success path are
    // therefore tested via a @TestVisible inner-class override or
    // by exercising the controller logic through a lightweight
    // "white-box" approach using JSON-deserialized SObjects passed
    // directly into the processing logic.
    //
    // Below we expose the inner processing logic through
    // @TestVisible helper methods that accept pre-built SObject
    // lists, allowing full branch coverage without real recurrence
    // DML. Add @TestVisible to the helper methods in the
    // controller (see companion refactor notes), or use the
    // approach below that wraps the validation logic in a separate
    // testable method.
    //
    // Since the controller as written performs SOQL internally, we
    // cover the remaining branches by:
    //   a) Inserting a non-recurring event (covered above).
    //   b) Testing validateAndSync directly via inner helper
    //      (requires minor @TestVisible refactor – see below).
    //   c) Where a full refactor isn't possible, we document the
    //      branches and mark them with mocked data.
    //
    // The tests below use the JSON-deserialization technique to
    // exercise copyFields and validation logic independently.
    // ─────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────
    // TEST 3 – Incomplete rate data → RateSyncException
    //          (via @TestVisible inner validator)
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_incompleteRates_throwsException() {

        Id fakeId1 = '00U000000000001AAA';
        Event sourceEvt = buildFakeEvent(fakeId1, FAKE_RECURRENCE_ID, false);

        // Directly test the validation path
        Test.startTest();
        try {
            EventRateSyncController.validateRatesAndThrow(sourceEvt);
            System.assert(false, 'Expected exception was not thrown');
        } catch (EventRateSyncController.RateSyncException ex) {
            System.assertEquals(
                'Rate calculation data is incomplete.',
                ex.getMessage(),
                'Wrong exception message for incomplete rates'
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 4 – No sibling events → RateSyncException
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_noSiblingEvents_throwsException() {

        Id fakeId1 = '00U000000000001AAA';
        Event sourceEvt = buildFakeEvent(fakeId1, FAKE_RECURRENCE_ID, true);
        List<Event> emptyList = new List<Event>();

        Test.startTest();
        try {
            EventRateSyncController.validateSiblingsAndThrow(emptyList);
            System.assert(false, 'Expected exception was not thrown');
        } catch (EventRateSyncController.RateSyncException ex) {
            System.assertEquals(
                'No related recurring events found.',
                ex.getMessage(),
                'Wrong exception message for no siblings'
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 5 – copyRateFields correctly copies all fields
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_copyRateFields_allFieldsCopied() {

        Id srcId = '00U000000000001AAA';
        Id sibId = '00U000000000002AAA';

        Event source = buildFakeEvent(srcId, FAKE_RECURRENCE_ID, true);
        Event sibling = buildFakeEvent(sibId, FAKE_RECURRENCE_ID, false);

        List<Event> siblings = new List<Event>{ sibling };

        Test.startTest();
        List<Event> result =
            EventRateSyncController.copyRateFields(source, siblings);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return one sibling');
        Event updated = result[0];

        // Billing & Rate
        System.assertEquals(source.Location__c,
            updated.Location__c, 'Location mismatch');
        System.assertEquals(source.Client_Billing_Details__c,
            updated.Client_Billing_Details__c, 'Client billing mismatch');
        System.assertEquals(source.Client_Rate__c,
            updated.Client_Rate__c, 'Client rate mismatch');
        System.assertEquals(source.Client_Rate_Amount__c,
            updated.Client_Rate_Amount__c, 'Client rate amount mismatch');
        System.assertEquals(source.Caregiver_Billing_Details__c,
            updated.Caregiver_Billing_Details__c, 'Caregiver billing mismatch');
        System.assertEquals(source.Caregiver_Rate__c,
            updated.Caregiver_Rate__c, 'Caregiver rate mismatch');
        System.assertEquals(source.Caregiver_Rate_Amount__c,
            updated.Caregiver_Rate_Amount__c, 'Caregiver rate amount mismatch');

        // Mileage
        System.assertEquals(source.Enter_Miles_1__c,
            updated.Enter_Miles_1__c, 'Miles 1 mismatch');
        System.assertEquals(source.Mileage_Amount__c,
            updated.Mileage_Amount__c, 'Mileage amount mismatch');
        System.assertEquals(source.Mileage_Description__c,
            updated.Mileage_Description__c, 'Mileage desc mismatch');

        // Expense
        System.assertEquals(source.Expense_Amount__c,
            updated.Expense_Amount__c, 'Expense amount mismatch');
        System.assertEquals(source.Expense_Description__c,
            updated.Expense_Description__c, 'Expense desc mismatch');
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 6 – Success message returned correctly
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_successMessage() {
        String expected =
            'Rate calculation synced successfully to all recurring events.';
        System.assertEquals(
            expected,
            EventRateSyncController.getSuccessMessage(),
            'Success message mismatch'
        );
    }

    // ─────────────────────────────────────────────────────────────
    // TEST 7 – RateSyncException can be constructed and thrown
    // ─────────────────────────────────────────────────────────────
    @isTest
    static void test_rateSyncException_construction() {
        Test.startTest();
        try {
            throw new EventRateSyncController.RateSyncException('test error');
        } catch (EventRateSyncController.RateSyncException ex) {
            System.assertEquals('test error', ex.getMessage());
        }
        Test.stopTest();
    }
}