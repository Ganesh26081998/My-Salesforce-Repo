/*
----------------------------------------------------------------------------
Author        : Siva Naga Prasad
Class Name    : ContactReferralMetricsBatch
CreatedOn     : 21-01-2026
LastModifiedOn: 21-05-2026
LastModifiedBy: Siva Naga Prasad
Description   : This batch class calculates and updates referral metrics 
                for business contacts by processing related contacts, 
                counting referred prospects and clients, calculating 
                lifetime revenue from Billing__c records, and updating 
                referral metric fields on Contact records. It also chains 
                OpportunityReferralMetricsBatch after completion.
----------------------------------------------------------------------------
*/

global class ContactReferralMetricsBatch implements Database.Batchable<SObject> {
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        
        Id businessRtId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('IndustriesBusiness').getRecordTypeId();
        System.debug('=== [START] ContactReferralMetricsBatch ===');
        
        if (businessRtId == null) {
            System.debug('ERROR: RecordType "IndustriesBusiness" not found! Query will return 0 records.');
        }
        
        return Database.getQueryLocator([SELECT Id FROM Contact WHERE RecordTypeId = :businessRtId]);
    }
    
    global void execute(Database.BatchableContext bc, List<Contact> scope) {
                
        if (scope.isEmpty()) {
            System.debug('WARNING: Scope is empty. Exiting execute.');
            return;
        }
        
        Set<Id> contactIds = new Set<Id>();
        for (Contact c : scope) {
            contactIds.add(c.Id);
        }
        
        /*Fetch Contact-Contact Relations*/
        Map<Id, Set<Id>> contactToRelatedContacts = new Map<Id, Set<Id>>();
        Set<Id> relatedContactIds = new Set<Id>();
        
        List<HealthCloudGA__ContactContactRelation__c> relations = [
            SELECT HealthCloudGA__Contact__c, HealthCloudGA__RelatedContact__c
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE HealthCloudGA__Contact__c IN :contactIds
            AND Is_Referral__c = TRUE
        ];
        
        if (relations.isEmpty()) {
            System.debug('All contacts in scope will get zeroed-out field values.');
        }
        
        for (HealthCloudGA__ContactContactRelation__c rel : relations) {
            
            if (!contactToRelatedContacts.containsKey(rel.HealthCloudGA__Contact__c)) {
                contactToRelatedContacts.put(rel.HealthCloudGA__Contact__c, new Set<Id>());
            }
            contactToRelatedContacts.get(rel.HealthCloudGA__Contact__c).add(rel.HealthCloudGA__RelatedContact__c);
            relatedContactIds.add(rel.HealthCloudGA__RelatedContact__c);
        }
                
        if (relatedContactIds.isEmpty()) {
            System.debug('WARNING: relatedContactIds is empty. Returning early — no updates will happen.');
            return;
        }
        
        /* Fetch Related Contacts Account Info */
        Map<Id, String> contactStageMap = new Map<Id, String>();
        Map<Id, Id> contactToAccountMap = new Map<Id, Id>();
        
        List<Contact> relatedContacts = [
            SELECT Id, AccountId, Account.Account_Status__c, Account.IsPersonAccount
            FROM Contact
            WHERE Id IN :relatedContactIds AND Account.IsPersonAccount = true
        ];
        
        if (relatedContacts.size() < relatedContactIds.size()) {
            // Log the excluded ones
            Set<Id> foundIds = new Set<Id>();
            for (Contact rc : relatedContacts) foundIds.add(rc.Id);
            for (Id rid : relatedContactIds) {
                if (!foundIds.contains(rid)) {
                    System.debug('Excluded RelatedContactId (not a person account or no account): ' + rid);
                }
            }
        }
        
        for (Contact related : relatedContacts) {
            contactToAccountMap.put(related.Id, related.AccountId);
            contactStageMap.put(related.Id, related.Account.Account_Status__c);
        }
        
        /* Count Prospects & Clients */
        Map<Id, Integer> prospectCountMap = new Map<Id, Integer>();
        Map<Id, Integer> clientCountMap   = new Map<Id, Integer>();
        Set<Id> patientAccountIds  = new Set<Id>();
        
        for (Id contactId : contactToRelatedContacts.keySet()) {
            for (Id relatedId : contactToRelatedContacts.get(contactId)) {
                
                String stage = contactStageMap.get(relatedId);
                Id accId = contactToAccountMap.get(relatedId);

                // if (stage == null) {
                //     System.debug('WARNING: Stage is NULL for RelatedId: ' + relatedId + '. This contact was likely excluded by the IsPersonAccount filter or has no Account_Status__c value.');
                // }
                
                if (accId != null) {
                    patientAccountIds.add(accId);
                }

                if (stage == 'Client') {
                    clientCountMap.put(contactId, (clientCountMap.get(contactId) == null ? 1 : clientCountMap.get(contactId) + 1));
                    //Id accId = contactToAccountMap.get(relatedId);
                    //clientAccountIds.add(accId);
                    
                } else if (String.isNotBlank(stage) && stage != 'Client') {
                    prospectCountMap.put(contactId, (prospectCountMap.get(contactId) == null ? 1 : prospectCountMap.get(contactId) + 1));
                    
                } else {
                    System.debug('SKIPPED (blank/null stage) → ContactId: ' + contactId + ' | RelatedId: ' + relatedId);
                }
            }
        }
        
        /* Calculate Lifetime Revenue */
        Map<Id, Decimal> accountRevenueMap = new Map<Id, Decimal>();
        
        if (!patientAccountIds.isEmpty()) {
            
            List<AggregateResult> revenueResults = [
                SELECT Client__c accId, SUM(Amount__c) totalRevenue
                FROM Billing__c
                WHERE Client__c IN :patientAccountIds
                GROUP BY Client__c
            ];
            
            if (revenueResults.isEmpty()) {
                System.debug('WARNING: No Billing__c records found for patientAccountIds: ' + patientAccountIds + '. Lifetime Revenue will be 0.');
            }
            
            for (AggregateResult ar : revenueResults) {
                Id accId = (Id) ar.get('accId');
                Decimal rev = (Decimal) ar.get('totalRevenue');
                System.debug('Billing Revenue → AccountId: ' + accId + ' | Total Revenue: ' + rev);
                accountRevenueMap.put(accId, rev);
            }
            
        } else {
            System.debug('WARNING: patientAccountIds is empty. Skipping Billing__c query. All Lifetime Revenue will be 0.');
        }
        
        /* Build contactRevenueMap */
        Map<Id, Decimal> contactRevenueMap = new Map<Id, Decimal>();
        
        for (Id contactId : contactToRelatedContacts.keySet()) {
            Decimal total = 0;
            for (Id relatedId : contactToRelatedContacts.get(contactId)) {
               // if (contactStageMap.get(relatedId) == 'Client') {
                    Id accId = contactToAccountMap.get(relatedId);
                    Decimal revenue = accountRevenueMap.containsKey(accId) ? accountRevenueMap.get(accId) : 0;
                    total += revenue;
               // }
            }
            contactRevenueMap.put(contactId, total);
        }
        
        /* Update Contacts */
        List<Contact> contactsToUpdate = new List<Contact>();
        
        for (Contact c : scope) {
            Integer prospects = prospectCountMap.containsKey(c.Id) ? prospectCountMap.get(c.Id) : 0;
            Integer clients   = clientCountMap.containsKey(c.Id)   ? clientCountMap.get(c.Id)   : 0;
            Decimal revenue   = contactRevenueMap.containsKey(c.Id) ? contactRevenueMap.get(c.Id) : 0;
                        
            contactsToUpdate.add(new Contact(
                Id = c.Id,
                Prospects_Referred__c = prospects,
                Clients_Referred__c   = clients,
                Lifetime_Revenue__c   = revenue,
                Records_Updated_On__c = System.now()
            ));
        }
        
        
        if (!contactsToUpdate.isEmpty()) {
            try {
                Database.SaveResult[] results = Database.update(contactsToUpdate, false); // allOrNone = false to catch partial failures
                Integer successCount = 0;
                Integer failCount = 0;
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successCount++;
                    } else {
                        failCount++;
                        for (Database.Error err : results[i].getErrors()) {
                            System.debug('FAILED update → ContactId: ' + contactsToUpdate[i].Id + ' | Error: ' + err.getMessage() + ' | Fields: ' + err.getFields() + ' | StatusCode: ' + err.getStatusCode());
                        }
                    }
                }
            } catch (Exception e) {
                System.debug('EXCEPTION during update: ' + e.getMessage() + ' | Line: ' + e.getLineNumber() + ' | Stack: ' + e.getStackTraceString());
            }
        } else {
            System.debug('WARNING: contactsToUpdate is empty. Nothing to update.');
        }
    }
    
    global void finish(Database.BatchableContext bc) {
        System.debug('=== [FINISH] ContactReferralMetricsBatch completed. Chaining OpportunityReferralMetricsBatch. ===');
        Database.executeBatch(new OpportunityReferralMetricsBatch(), 200);
    }
}