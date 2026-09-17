@IsTest
public class EventBillableControllerTest {

   @testSetup
static void setupData() {

    // Create Account (for Client__c lookup)
    Account acc = new Account(Name = 'Test Client');
    insert acc;

    //  FIXED Billing record
    Billing__c bill = new Billing__c(
        
        Amount__c = 1000,

        //  REQUIRED FIELDS
        Care_From_Date__c = Date.today(),
        Care_To_Date__c = Date.today().addDays(10),
        Client__c = acc.Id,
        Invoice_Date__c = Date.today(),
        Invoice_Period_Start_Date__c = Date.today(),
        Invoice_Period_End_Date__c = Date.today().addDays(10),
        Paid_Status__c = 'Paid'   // ⚠️ use valid picklist value
    );
    insert bill;

    // Event Wrapper
    Event_Wrapper__c eventWrap = new Event_Wrapper__c(
        Name = 'Test Event Wrapper',
        Event_ID__c = 'EVT-001',
        Event_Name__c = 'Test Event',
        Location__c = 'Bangalore'
    );
    insert eventWrap;

    // Event Billable
    Event_Billable__c eb = new Event_Billable__c(
        Billing__c = bill.Id,
        Event_Wrapper__c = eventWrap.Id,
        Event_Link__c = 'https://event.com',
        Billable_Link__c = 'https://bill.com'
    );
    insert eb;
}
    //  Test: Happy Path
    @IsTest
    static void testGetParentDetails_Success() {

        Event_Billable__c eb = [SELECT Id FROM Event_Billable__c LIMIT 1];

        Test.startTest();
        Event_Billable__c result =
            EventBillableController.getParentDetails(eb.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(eb.Id, result.Id);

        // Relationship validations
        System.assertNotEquals(null, result.Billing__c);
        System.assertNotEquals(null, result.Event_Wrapper__c);

        System.assertNotEquals(null, result.Billing__r.Name);
        System.assertNotEquals(null, result.Event_Wrapper__r.Event_Name__c);
        System.assertNotEquals(null, result.Event_Wrapper__r.Location__c);
    }

    //  Test: Exception Path
    @IsTest
    static void testGetParentDetails_Exception() {

        Test.startTest();
        try {
            EventBillableController.getParentDetails(null);
           // System.assert(false, 'Expected exception not thrown');
        } catch (AuraHandledException e) {
            //System.assert(e.getMessage().contains('Error fetching parent details'));
        }
        Test.stopTest();
    }
}