/*
----------------------------------------------------------------------------
Author        : Bhanu Prakash
Class Name    : LocationSharingHandler
CreatedOn     : 18-03-2026
LastModifiedOn: 15-05-2026
LastModifiedBy: Bhanu Prakash
Description   : This class is used to manage location-based sharing for Account and Contact records by automatically creating and removing manual sharing access for users based on city assignments.




----------------------------------------------------------------------------
*/



public with sharing class LocationSharingHandler {

    private static final Set<String> ACCOUNT_RECORDTYPE_DEV_NAMES =
        new Set<String>{ 'Business_Account', 'Prospect' };

    private static final String ACCOUNT_LOCATION_FIELD = 'Location_g__c';
    private static final String CONTACT_LOCATION_FIELD = 'Location__c';
    private static final String LOCATION_MATCH_FIELD = 'City__c';
    private static final String ACCOUNT_ACCESS_LEVEL = 'Edit';
    private static final String CONTACT_ACCESS_LEVEL = 'Edit';
    private static final String OPPORTUNITY_ACCESS_LEVEL = 'Edit';

    public static void handleAccounts(
        List<Account> newList,
        Map<Id, Account> oldMap,
        Boolean isInsert,
        Boolean isUpdate
    ) {

        
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> allowedRtIds =
            getAccountRecordTypeIdsByDeveloperNames(ACCOUNT_RECORDTYPE_DEV_NAMES);


        Map<Id, String> accountToLocation = new Map<Id, String>();
        Set<String> locationValues = new Set<String>();
        Set<Id> accountIdsToReset = new Set<Id>();

        for (Account acc : newList) {           

            if (!allowedRtIds.contains(acc.RecordTypeId)) {            
                continue;
            }

            Boolean shouldProcess = isInsert;

            if (isUpdate && oldMap != null && oldMap.containsKey(acc.Id)) {             

                shouldProcess = acc.Location_g__c != oldMap.get(acc.Id).Location_g__c;
            }        

            if (!shouldProcess) {
                continue;
            }

            accountIdsToReset.add(acc.Id);
       
            String locationValue =
                (String) acc.get(ACCOUNT_LOCATION_FIELD);

            

            if (String.isBlank(locationValue)) {
                
                continue;
            }

            locationValue = locationValue.trim();           

            accountToLocation.put(acc.Id, locationValue);
            locationValues.add(locationValue);
        }

        if (accountIdsToReset.isEmpty()) {
            
            return;
        }

        deleteAccountShares(accountIdsToReset);

        if (locationValues.isEmpty()) {
            
            return;
        }

        Map<String, Set<Id>> locationToUsers =
            getLocationToUsers(locationValues);

        

        List<AccountShare> sharesToInsert =
            buildAccountShares(accountToLocation, locationToUsers);

        

        if (!sharesToInsert.isEmpty()) {

            Database.SaveResult[] results = Database.insert(sharesToInsert, false);

            
        }

        
    }

    private static List<AccountShare> buildAccountShares(
        Map<Id, String> accountToLocation,
        Map<String, Set<Id>> locationToUsers
    ) {

        List<AccountShare> sharesToInsert =
            new List<AccountShare>();

        Set<String> uniquePairs = new Set<String>();

        for (Id accountId : accountToLocation.keySet()) {            

            String locationValue =
                accountToLocation.get(accountId);

            
            if (!locationToUsers.containsKey(locationValue)) {
                
                continue;
            }

            for (Id userId : locationToUsers.get(locationValue)) {

                

                String pairKey =
                    String.valueOf(accountId) + '-' +
                    String.valueOf(userId);

                

                if (uniquePairs.contains(pairKey)) {
                    
                    continue;
                }

                uniquePairs.add(pairKey);

                AccountShare shareRow = new AccountShare();
                shareRow.AccountId = accountId;
                shareRow.UserOrGroupId = userId;
                shareRow.AccountAccessLevel = ACCOUNT_ACCESS_LEVEL;
                shareRow.OpportunityAccessLevel = OPPORTUNITY_ACCESS_LEVEL;
                shareRow.RowCause = Schema.AccountShare.RowCause.Manual;

                

                sharesToInsert.add(shareRow);
            }
        }

        

        return sharesToInsert;
    }

    private static void deleteAccountShares(Set<Id> accountIds) {

        

        if (accountIds == null || accountIds.isEmpty()) {
            
            return;
        }

        List<AccountShare> sharesToDelete = [
            SELECT Id
            FROM AccountShare
            WHERE AccountId IN :accountIds
            AND RowCause = 'Manual'
        ];

        

        if (!sharesToDelete.isEmpty()) {

            //delete sharesToDelete;
            Database.DeleteResult[] results = Database.delete(sharesToDelete, false);

for (Integer i = 0; i < results.size(); i++) {
    if (!results[i].isSuccess()) {
        System.debug('Failed Share Id: ' + sharesToDelete[i].Id);
        for (Database.Error err : results[i].getErrors()) {
            System.debug(err.getStatusCode() + ' : ' + err.getMessage());
        }
    }
}
            
        }
    }

    public static void handleContacts(
        List<Contact> newList,
        Map<Id, Contact> oldMap,
        Boolean isInsert,
        Boolean isUpdate
    ) {

        
        if (newList == null || newList.isEmpty()) {
            
            return;
        }

        Map<Id, String> contactToLocation =
            new Map<Id, String>();

        Set<String> locationValues = new Set<String>();
        Set<Id> contactIdsToReset = new Set<Id>();

        for (Contact con : newList) {

        

            Boolean shouldProcess = isInsert;

            if (isUpdate && oldMap != null && oldMap.containsKey(con.Id)) {

                

                shouldProcess =
                    con.Location__c != oldMap.get(con.Id).Location__c;
            }

            

            if (!shouldProcess) {
                continue;
            }

            contactIdsToReset.add(con.Id);

            

            String rawValue =
                (String) con.get(CONTACT_LOCATION_FIELD);

            

            if (String.isBlank(rawValue)) {
                
                continue;
            }

            rawValue = rawValue.trim();           
            contactToLocation.put(con.Id, rawValue);
            locationValues.add(rawValue);

        }

        if (contactIdsToReset.isEmpty()) {
        
            return;
        }

        deleteContactShares(contactIdsToReset);

        if (locationValues.isEmpty()) {
            
            return;
        }

        Map<String, Set<Id>> locationToUsers =
            getLocationToUsers(locationValues);

        

        List<ContactShare> sharesToInsert =
            buildContactShares(contactToLocation, locationToUsers);

        

        if (!sharesToInsert.isEmpty()) {

            Database.SaveResult[] results =
                Database.insert(sharesToInsert, false);

            
        }

        
    }

    private static List<ContactShare> buildContactShares(
        Map<Id, String> contactToLocation,
        Map<String, Set<Id>> locationToUsers
    ) {

        List<ContactShare> sharesToInsert =
            new List<ContactShare>();

        Set<String> uniquePairs = new Set<String>();

        for (Id contactId : contactToLocation.keySet()) {

            

            String locationValue =
                contactToLocation.get(contactId);

            

            if (!locationToUsers.containsKey(locationValue)) {
                
                continue;
            }

            for (Id userId : locationToUsers.get(locationValue)) {

                

                String pairKey =
                    String.valueOf(contactId) + '-' +
                    String.valueOf(userId);

                

                if (uniquePairs.contains(pairKey)) {
                    
                    continue;
                }

                uniquePairs.add(pairKey);

                ContactShare shareRow = new ContactShare();
                shareRow.ContactId = contactId;
                shareRow.UserOrGroupId = userId;
                shareRow.ContactAccessLevel = CONTACT_ACCESS_LEVEL;
                shareRow.RowCause =
                    Schema.ContactShare.RowCause.Manual;

                

                sharesToInsert.add(shareRow);
            }
        }

        

        return sharesToInsert;
    }

    private static void deleteContactShares(Set<Id> contactIds) {

        

        if (contactIds == null || contactIds.isEmpty()) {
            
            return;
        }

        List<ContactShare> sharesToDelete = [
            SELECT Id
            FROM ContactShare
            WHERE ContactId IN :contactIds
            AND RowCause = 'Manual'
        ];

        

        if (!sharesToDelete.isEmpty()) {

            delete sharesToDelete;

            
        }
    }

    private static Map<String, Set<Id>> getLocationToUsers(
        Set<String> locationValues
    ) {

        

        Map<String, Set<Id>> locationToUsers =
            new Map<String, Set<Id>>();

        if (locationValues == null || locationValues.isEmpty()) {
            
            return locationToUsers;
        }

        for (User_City_Assignment__c assignment : [
            SELECT User__c,
                   WellSpring_Location__r.City__c
            FROM User_City_Assignment__c
            WHERE User__c != null
            AND WellSpring_Location__c != null
            AND WellSpring_Location__r.City__c IN :locationValues
        ]) {

            

            String cityValue =
                assignment.WellSpring_Location__r.City__c;

            

            if (String.isBlank(cityValue)) {
                
                continue;
            }

            cityValue = cityValue.trim();

            

            if (!locationToUsers.containsKey(cityValue)) {

                locationToUsers.put(
                    cityValue,
                    new Set<Id>()
                );

                
            }

            locationToUsers.get(cityValue)
                .add(assignment.User__c);

            
        }

        

        return locationToUsers;
    }

    private static Set<Id> getAccountRecordTypeIdsByDeveloperNames(
        Set<String> developerNames
    ) {

    

        Set<Id> recordTypeIds = new Set<Id>();

        Map<String, Schema.RecordTypeInfo> rtInfoByDevName =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName();

        

        for (String devName : developerNames) {

            

            if (rtInfoByDevName.containsKey(devName)) {

                recordTypeIds.add(
                    rtInfoByDevName.get(devName)
                        .getRecordTypeId()
                );

            }
        }

    

        return recordTypeIds;
    }
}