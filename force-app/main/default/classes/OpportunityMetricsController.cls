/*
----------------------------------------------------------------------------
Author         : Ganesh Uppin
Class Name     : OpportunityMetricsController
CreatedOn      : 13-01-2026
LastModifiedOn : 10-05-2026
LastModifiedBy : Ganesh Uppin

Description    : This class is used to fetch Opportunity referral metrics
                 and trigger batch processing to refresh Opportunity data.
                 It retrieves referral statistics, lifetime revenue, and
                 executes batch jobs to update Opportunity metrics.
----------------------------------------------------------------------------
*/
public with sharing class OpportunityMetricsController {

    // 🔹 Fetch Opportunity Metrics
    @AuraEnabled(cacheable=true)
    public static Opportunity getOpportunityMetrics(Id opportunityId) {
        return [
            SELECT Id,
                   Prospects_Referred__c,
                   Clients_Referred__c,
                   Lifetime_Revenue__c,
                   LastModifiedDate
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
    }

    // 🔹 Run Batch for Opportunity
    @AuraEnabled
    public static void runOpportunityBatch() {
        Database.executeBatch(new OpportunityReferralMetricsBatch(), 200);
    }
}