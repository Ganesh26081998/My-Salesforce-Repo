public with sharing class UpdateFamilyContactsInvocable {

    public class Request {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    @InvocableMethod(label='Update Family Contacts')
    public static void updateFamilyContacts(List<Request> requests) {

        if(requests == null || requests.isEmpty()){
            return;
        }

        // Collect Account Ids
        Set<Id> accountIds = new Set<Id>();

        for(Request req : requests){
            if(req.accountId != null){
                accountIds.add(req.accountId);
            }
        }

        if(accountIds.isEmpty()){
            return;
        }

        // Get Account Details
        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id,
                   PersonContactId,
                   Account_Status__c,
                   Account_Statusp__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        // Map<PersonContactId, AccountId>
        Map<Id, Id> personContactToAccountMap = new Map<Id, Id>();

        for(Account acc : accountMap.values()){
            if(acc.PersonContactId != null){
                personContactToAccountMap.put(acc.PersonContactId, acc.Id);
            }
        }

        if(personContactToAccountMap.isEmpty()){
            return;
        }

        // Get all Family Relationships
        List<HealthCloudGA__ContactContactRelation__c> relations = [
            SELECT Id,
                   HealthCloudGA__Contact__c,
                   HealthCloudGA__RelatedContact__c,
                   HealthCloudGA__Active__c,
                   Type__c
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE HealthCloudGA__Contact__c IN :personContactToAccountMap.keySet()
            AND HealthCloudGA__Active__c = true
            AND Type__c = 'Family Contact'
        ];

        if(relations.isEmpty()){
            return;
        }

        // Map<FamilyContactId, Account>
        Map<Id, Account> familyContactAccountMap = new Map<Id, Account>();

        for(HealthCloudGA__ContactContactRelation__c rel : relations){

            Id accountId = personContactToAccountMap.get(rel.HealthCloudGA__Contact__c);

            if(accountId != null){

                familyContactAccountMap.put(
                    rel.HealthCloudGA__RelatedContact__c,
                    accountMap.get(accountId)
                );
            }
        }

        if(familyContactAccountMap.isEmpty()){
            return;
        }

        // Query Family Contacts
        List<Contact> contactsToUpdate = [
            SELECT Id,
                   Account_Stage_in_Contact__c,
                   Account_Status_in_Contact__c
            FROM Contact
            WHERE Id IN :familyContactAccountMap.keySet()
        ];

        // Update Contact Fields
        for(Contact con : contactsToUpdate){

            Account acc = familyContactAccountMap.get(con.Id);

            if(acc != null){

                // Account Stage
                con.Account_Stage_in_Contact__c = acc.Account_Status__c;

                // Account Status
                con.Account_Status_in_Contact__c = acc.Account_Statusp__c;
            }
        }

        if(!contactsToUpdate.isEmpty()){
            update contactsToUpdate;
        }
    }
}