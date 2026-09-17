@isTest
private class EventWrapperSyncTest {

    @isTest
    static void testEventWrapperCreation() {

        // Create test Event
        Event testEvent = new Event(
            Subject = 'Test Meeting',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1)
        );

        Test.startTest();
        insert testEvent;
        Test.stopTest();

        // Verify wrapper record created
        List<Event_Wrapper__c> wrappers = [
            SELECT Id, Name, Event_Name__c, Event_ID__c
            FROM Event_Wrapper__c
            WHERE Event_ID__c = :testEvent.Id
        ];

        
    }
}