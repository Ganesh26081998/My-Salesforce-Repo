/*
----------------------------------------------------------------------------
Author        : Prasad Patil
Class Name    : BusinessAccountContactMetricsController
CreatedOn     : 05-03-2026
LastModifiedOn: 08-05-2026
LastModifiedBy: Siva Naga Prasad
Description   : Controller class to retrieve, aggregate, and update 
                referral metrics and business stage information for 
                Business Account contacts.
----------------------------------------------------------------------------
*/

public with sharing class BusinessAccountContactMetricsController {

    public class ContactMetricsSummary {
        @AuraEnabled public Decimal lifetimeRevenue;
        @AuraEnabled public Decimal clientsReferred;
        @AuraEnabled public Decimal prospectsReferred;

        public ContactMetricsSummary() {
            this.lifetimeRevenue = 0;
            this.clientsReferred = 0;
            this.prospectsReferred = 0;
        }
    }

    @AuraEnabled(cacheable=true)
    public static ContactMetricsSummary getContactMetricsSummary(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required');
        }

        ContactMetricsSummary summary = new ContactMetricsSummary();
        try {
            AggregateResult[] results = [
                SELECT
                    SUM(Lifetime_Revenue__c) totalRevenue,
                    SUM(Clients_Referred__c) totalClients,
                    SUM(Prospects_Referred__c) totalProspects
                FROM Contact
                WHERE AccountId = :accountId
            ];

            if (!results.isEmpty()) {
                AggregateResult result = results[0];
                summary.lifetimeRevenue = result.get('totalRevenue') != null ? (Decimal) result.get('totalRevenue') : 0;
                summary.clientsReferred = result.get('totalClients') != null ? (Decimal) result.get('totalClients') : 0;
                summary.prospectsReferred = result.get('totalProspects') != null ? (Decimal) result.get('totalProspects') : 0;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving contact metrics: ' + e.getMessage());
        }
        return summary;
    }

    @AuraEnabled
    public static void runAccountBatch() {
        try {
            Database.executeBatch(new BusinessAccountMetricsBatch(), 200);
        } catch(Exception e) {
            throw new AuraHandledException('Failed to initiate backend calculation batch: ' + e.getMessage());
        }
    }
}