/*
----------------------------------------------------------------------------
Author        : Bhanu Prakash
Class Name    : ClientAccountTeamController
CreatedOn     : 18-01-2026
LastModifiedOn: 02-05-2026
LastModifiedBy: Bhanu Prakash
Description   : This class is used to manage internal and external client account team users by supporting search, create, update, retrieve, and delete operations for Client User Detail records.


----------------------------------------------------------------------------
*/


public with sharing class ClientAccountTeamController {
    
    @AuraEnabled(cacheable=true)
    public static List<List<Client_User_Detail__c>> getClientUsers(Id accountId) {
        List<Client_User_Detail__c> users = [
            SELECT Id,
                   Client__c,
                   User__c,
                   User__r.Phone,
                   User__r.Email,
                   External_User_Name__c,
                   External_User_Phone__c,
                   External_User_Email__c,
                   Marketing_Attribution__c,
                   Role__c
            FROM Client_User_Detail__c
            WHERE Client__c = :accountId 
            ORDER BY CreatedDate DESC
        ];
        List<Client_User_Detail__c> internalUsers = new List<Client_User_Detail__c>();
        List<Client_User_Detail__c> externalUsers = new List<Client_User_Detail__c>();

        for (Client_User_Detail__c user : users) {
            if (user.User__c == null) {
                externalUsers.add(user);
            } else {
                internalUsers.add(user);
            }
        }
        
            return new List<List<Client_User_Detail__c>> {
                internalUsers,
                externalUsers   
            };
   
    }

    @AuraEnabled(cacheable=true)
    public static List<User> searchInternalUsers(String searchKey) {
        String searchPattern = '%' + searchKey + '%';
        return [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = true
            AND Name LIKE :searchPattern
            ORDER BY Name
            LIMIT 20
        ];
    }

   
    @AuraEnabled
    public static void saveClientUser(
        Id clientId,
        Id userId,
        String externalName,
        String externalEmail,
        String externalPhone,
        String role,
        String marketingAttribution,
        Id recordId
    ) {
        if (clientId == null) {
            throw new AuraHandledException('Client ID is required');
        }

        Client_User_Detail__c record;

        if (recordId != null) {

            record = [
                SELECT Id, User__c
                FROM Client_User_Detail__c
                WHERE Id = :recordId
                LIMIT 1
            ];

        } else {


            record = new Client_User_Detail__c();
            record.Client__c = clientId;

            
            if (userId != null) {
                List<Client_User_Detail__c> existing = [
                    SELECT Id
                    FROM Client_User_Detail__c
                    WHERE Client__c = :clientId
                    AND User__c = :userId
                    LIMIT 1
                ];

                if (!existing.isEmpty()) {
                    throw new AuraHandledException('This user is already added to the account team');
                }
            }
        }


    if (userId != null) {
        User selectedUser = [SELECT Name FROM User WHERE Id = :userId LIMIT 1];

        record.User__c = userId;
        record.External_User_Name__c = selectedUser.Name;

    } else if (String.isNotBlank(externalName)) {
        record.User__c = null;
        record.External_User_Name__c = externalName;
        record.External_User_Email__c = externalEmail;
        record.External_User_Phone__c = externalPhone;

    } else {
        throw new AuraHandledException('Either internal user or external user name must be provided');
    }

    record.Role__c = role;
    record.Marketing_Attribution__c = marketingAttribution;

        try {
            if (recordId != null) {
                update record;  
            } else {
                insert record;  
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Error saving: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteClientUser(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record ID is required');
        }
        
        try {

             if (!Schema.sObjectType.Client_User_Detail__c.isDeletable()) {
            throw new AuraHandledException(
                'You do not have permission to delete this relationship.'
            );
        }
            delete [SELECT Id FROM Client_User_Detail__c WHERE Id = :recordId LIMIT 1];
        } catch (DmlException e) {
            throw new AuraHandledException('Error deleting: ' + e.getMessage());
        }
    }
}