/*
----------------------------------------------------------------------------
Author        : Siva Naga Prasad
Class Name    : ContactReferralMetricsController
CreatedOn     : 21-01-2026
LastModifiedOn: 21-05-2026
LastModifiedBy: Siva Naga Prasad
Description   : This class is used for Contact Referral Metrics component to read the fields values.
----------------------------------------------------------------------------
*/
public with sharing class ContactReferralMetricsController {

    @AuraEnabled(cacheable=true)
    public static Contact getContactMetrics(Id contactId) {
        return [
            SELECT Id,
                   Prospects_Referred__c,
                   Clients_Referred__c,
                   Lifetime_Revenue__c,
                   Records_Updated_On__c
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static void runBatch() {
        Database.executeBatch(new ContactReferralMetricsBatch(), 200);
    }
}