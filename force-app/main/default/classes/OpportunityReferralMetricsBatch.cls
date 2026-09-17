/*
----------------------------------------------------------------------------
Author         : Ganesh Uppin
Class Name     : OpportunityReferralMetricsBatch
CreatedOn      : 13-01-2026
LastModifiedOn : 10-05-2026
LastModifiedBy : Ganesh Uppin

Description    : This batch class is used to calculate and update Opportunity
                 referral metrics by fetching referral details from Primary
                 Contact or rolling up values from Account-related Contacts.
                 It updates Prospects Referred, Clients Referred, Lifetime
                 Revenue, and dynamically changes Opportunity stages based
                 on total referral counts.
----------------------------------------------------------------------------
*/
global class OpportunityReferralMetricsBatch implements Database.Batchable<SObject> {

   
    global Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator([
        SELECT Id, StageName, AccountId,
               Primary_Contact__c,
               Primary_Contact__r.Prospects_Referred__c,
               Primary_Contact__r.Clients_Referred__c,
               Primary_Contact__r.Lifetime_Revenue__c
        FROM Opportunity
        WHERE AccountId != null OR Primary_Contact__c != null
    ]);
}

global void execute(Database.BatchableContext bc, List<Opportunity> scope) {
    Set<Id> accountIds = new Set<Id>();

    for (Opportunity opp : scope) {
        if (opp.AccountId != null) {
            accountIds.add(opp.AccountId);
        }
    }

    // Get all contacts for account rollup case (Primary_Contact__c is blank)
    Map<Id, List<Contact>> accountContactsMap = new Map<Id, List<Contact>>();
    if (!accountIds.isEmpty()) {
        for (Contact c : [
            SELECT Id, AccountId,
                   Prospects_Referred__c,
                   Clients_Referred__c,
                   Lifetime_Revenue__c
            FROM Contact
            WHERE AccountId IN :accountIds
        ]) {
            if (!accountContactsMap.containsKey(c.AccountId)) {
                accountContactsMap.put(c.AccountId, new List<Contact>());
            }
            accountContactsMap.get(c.AccountId).add(c);
        }
    }

    List<Opportunity> oppsToUpdate = new List<Opportunity>();

    for (Opportunity opp : scope) {
        Integer prospects = 0;
        Integer clients = 0;
        Decimal revenue = 0;

        // CASE 1: If Primary Contact exists, copy values from that contact
        if (opp.Primary_Contact__c != null) {
            prospects = (Integer)(opp.Primary_Contact__r.Prospects_Referred__c == null ? 0 : opp.Primary_Contact__r.Prospects_Referred__c);
            clients   = (Integer)(opp.Primary_Contact__r.Clients_Referred__c == null ? 0 : opp.Primary_Contact__r.Clients_Referred__c);
            revenue   = (opp.Primary_Contact__r.Lifetime_Revenue__c == null ? 0 : opp.Primary_Contact__r.Lifetime_Revenue__c);
        }
        // CASE 2: If Primary Contact is blank but Account exists, roll up all related contacts
        else if (opp.AccountId != null) {
            List<Contact> contacts = accountContactsMap.get(opp.AccountId);
            if (contacts != null) {
                for (Contact c : contacts) {
                    prospects += (Integer)(c.Prospects_Referred__c == null ? 0 : c.Prospects_Referred__c);
                    clients   += (Integer)(c.Clients_Referred__c == null ? 0 : c.Clients_Referred__c);
                    revenue   += (c.Lifetime_Revenue__c == null ? 0 : c.Lifetime_Revenue__c);
                }
            }
        }

        Integer totalReferrals = prospects + clients;
        String newStage = opp.StageName;

        if (totalReferrals >= 2 && totalReferrals <= 3) {
            newStage = 'Referrals 2-3 within 30 days';
        } else if (totalReferrals > 3) {
            newStage = 'Referrals 4-8 within 90 days';
        }

        oppsToUpdate.add(new Opportunity(
            Id = opp.Id,
            Prospects_Referred__c = prospects,
            Clients_Referred__c   = clients,
            Lifetime_Revenue__c   = revenue,
            StageName             = newStage
        ));
    }

    if (!oppsToUpdate.isEmpty()) {
        update oppsToUpdate;
    }
}


    global void finish(Database.BatchableContext bc) {
        System.debug('OpportunityReferralMetricsBatch completed.');
    }
}