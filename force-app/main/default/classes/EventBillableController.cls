public with sharing class EventBillableController {
    
    @AuraEnabled(cacheable=true)
    public static Event_Billable__c getParentDetails(Id recordId) {
        try {
            return [
                SELECT Id, 
                       Billing__c, 
                       Billing__r.Name, 
                       Billing__r.Amount__c, 
                       Billing__r.Client__c,
                       Event_Wrapper__c, 
                       Event_Wrapper__r.Name, 
                       Event_Wrapper__r.Event_ID__c,
                       Event_Wrapper__r.Event_Name__c,
                       Event_Wrapper__r.Location__c,  // ← ADD THIS LINE
                       Event_Link__c,
                       Billable_Link__c
                FROM Event_Billable__c 
                WHERE Id = :recordId 
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching parent details: ' + e.getMessage());
        }
    }
}