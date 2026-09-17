/*
----------------------------------------------------------------------------
Author        : Bhanu Prakash
Class Name    : PatientContactRelationshipController
CreatedOn     : 13-03-2026
LastModifiedOn: 18-05-2026
LastModifiedBy: Bhanu Prakash
Description   : This class is used for Creating a relationship between prospects and contacts

----------------------------------------------------------------------------
*/

public with sharing class PatientContactRelationshipController {

    private static final String CCR_TYPE_CALLER = 'Caller';
    private static final String CCR_TYPE_INDIVIDUAL = 'Family Contact';
    private static void preventDuplicateFamilyRelation(Id contactId, Id relatedContactId) {
        List<HealthCloudGA__ContactContactRelation__c> existingRelations = [
            SELECT Id
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE HealthCloudGA__Contact__c = :contactId
            AND HealthCloudGA__RelatedContact__c = :relatedContactId
            AND Type__c IN :new Set<String>{ CCR_TYPE_CALLER, CCR_TYPE_INDIVIDUAL }
            LIMIT 1
        ];

        if (!existingRelations.isEmpty()) {
            throw new AuraHandledException('This Family Contact is already related to the client.');
        }
    }

    private static void preventDuplicateCoupleHouseholdRelation(Id contactId, Id relatedContactId) {
        List<HealthCloudGA__ContactContactRelation__c> existingRelations = [
            SELECT Id
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE Type__c = 'Couple Household'
            AND (
                (HealthCloudGA__Contact__c = :contactId AND HealthCloudGA__RelatedContact__c = :relatedContactId)
                OR
                (HealthCloudGA__Contact__c = :relatedContactId AND HealthCloudGA__RelatedContact__c = :contactId)
            )
            LIMIT 1
        ];

        if (!existingRelations.isEmpty()) {
            throw new AuraHandledException('This Couple Household relationship already exists.');
        }
    }

    
    private static void preventDuplicateOrganizationRelation(
            Id contactId,
            Id relatedContactId,
            Boolean isReferral
        ) {
    
        if (isReferral == true) {
            List<HealthCloudGA__ContactContactRelation__c> existingReferralRelations = [
                SELECT Id
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE HealthCloudGA__RelatedContact__c = :relatedContactId
                AND Type__c = 'Business Contact'
                AND Is_Referral__c = true
                LIMIT 1
            ];

            if (!existingReferralRelations.isEmpty()) {
                throw new AuraHandledException(
                    'A referral Business Contact already exists for this client.'
                );
            }
        } else {
        
            List<HealthCloudGA__ContactContactRelation__c> existingRelations = [
                SELECT Id
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE HealthCloudGA__Contact__c = :contactId
                AND HealthCloudGA__RelatedContact__c = :relatedContactId
                AND Type__c = 'Business Contact'
                LIMIT 1
            ];

            if (!existingRelations.isEmpty()) {
                throw new AuraHandledException(
                    'This Business Contact is already related to the client.'
                );
            }
        }
    }
    

    @AuraEnabled(cacheable=true)
    public static List<HealthCloudGA__ContactContactRelation__c> getRelatedContacts(String accountId) {

        if (String.isBlank(accountId)) {
            return new List<HealthCloudGA__ContactContactRelation__c>();
        }

        try {
            Account personAccount = [
                SELECT Id, PersonContactId
                FROM Account
                WHERE Id = :accountId
                AND IsPersonAccount = true
                LIMIT 1
            ];

            System.debug('personAccount: ' + personAccount);

            return [
                SELECT Id,
                    CreatedDate,
                    HealthCloudGA__Contact__c,
                    HealthCloudGA__Contact__r.Name,
                    HealthCloudGA__Contact__r.Phone,
                    HealthCloudGA__Contact__r.Email,
                    HealthCloudGA__Contact__r.Additional_duties__c,
                    Type__c,
                    HealthCloudGA__Role__r.Name,
                    Relationship_to_Client__c,
                    Family_Relationship__c,
                    Other_Relationship_to_Client__c,
                    Is_Referral__c
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE HealthCloudGA__RelatedContact__c = :personAccount.PersonContactId
                ORDER BY CREATEDDATE DESC            
            ];

        } catch (Exception e) {
            throw new AuraHandledException('Error fetching related contacts: ' + e.getMessage());
        }
    }


    @AuraEnabled(cacheable=false)
    public static Id getHouseholdAccountForPerson(Id personAccountId) {
        if (personAccountId == null) return null;

        Account pa = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE Id = :personAccountId
            AND IsPersonAccount = true
            LIMIT 1
        ];

        if (pa.PersonContactId == null) return null;

        List<AccountContactRelation> acrs = [
            SELECT AccountId
            FROM AccountContactRelation
            WHERE ContactId = :pa.PersonContactId
            AND Account.RecordType.DeveloperName = 'IndustriesHousehold'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return acrs.isEmpty() ? null : acrs[0].AccountId;
    }

    @AuraEnabled
    public static Id createPatientCCR(Id patientAccountId, Id relatedAccountId, Id roleId) {

        if (patientAccountId == relatedAccountId) {
            throw new AuraHandledException('You cannot relate a patient to itself.');
        }

        Map<Id, Account> accountMap = new Map<Id, Account>(
            [
                SELECT Id, PersonContactId
                FROM Account
                WHERE Id IN :new List<Id>{ patientAccountId, relatedAccountId }
                AND IsPersonAccount = true
            ]
        );

        if (!accountMap.containsKey(patientAccountId) ||
            !accountMap.containsKey(relatedAccountId)) {
            throw new AuraHandledException('Invalid Person Account.');
        }

        HealthCloudGA__ContactContactRelation__c ccr = new HealthCloudGA__ContactContactRelation__c();
        ccr.HealthCloudGA__Contact__c =  accountMap.get(patientAccountId).PersonContactId;
        ccr.HealthCloudGA__RelatedContact__c = accountMap.get(relatedAccountId).PersonContactId;
        ccr.HealthCloudGA__Role__c = roleId;
        ccr.Type__c = 'Couple Household';

        
        preventDuplicateCoupleHouseholdRelation(
            accountMap.get(patientAccountId).PersonContactId,
            accountMap.get(relatedAccountId).PersonContactId
        );

        insert ccr;

        return ccr.Id;
    }

    @AuraEnabled
    public static Id createBusinessCCR(
        Id businessContactId,
        Id relatedAccountId,
        String roleName,
        Boolean isReferral
    ) {
        try {
            if (businessContactId == null) {
                throw new AuraHandledException('Business Contact is required.');
            }

            if (relatedAccountId == null) {
                throw new AuraHandledException('Related Account is required.');
            }

            if (String.isBlank(roleName)) {
                throw new AuraHandledException('Type is required.');
            }

            Account acc = [
                SELECT PersonContactId
                FROM Account
                WHERE Id = :relatedAccountId
                AND IsPersonAccount = true
                LIMIT 1
            ];

            if (acc.PersonContactId == null) {
                throw new AuraHandledException('Invalid Person Account.');
            }

            List<HealthCloudGA__ReciprocalRole__c> roleList = [
                SELECT Id, Name
                FROM HealthCloudGA__ReciprocalRole__c
                WHERE Name = :roleName
                LIMIT 1
            ];

            if (roleList.isEmpty()) {
                throw new AuraHandledException('No Reciprocal Role found matching the selected Type.');
            }

            Contact businessContact = [
                SELECT Id, ReferralType__c
                FROM Contact
                WHERE Id = :businessContactId
                LIMIT 1
            ];

            if (String.isBlank(businessContact.ReferralType__c)) {
                throw new AuraHandledException('Type must be selected on Business Contact.');
            }

            if (businessContact.ReferralType__c != roleName) {
                throw new AuraHandledException('Selected Type does not match the saved Business Contact Type.');
            }

            HealthCloudGA__ContactContactRelation__c ccr =
                new HealthCloudGA__ContactContactRelation__c();

            ccr.HealthCloudGA__Contact__c = businessContactId;
            ccr.HealthCloudGA__RelatedContact__c = acc.PersonContactId;
            ccr.HealthCloudGA__Role__c = roleList[0].Id;            
            ccr.Type__c = 'Business Contact';
            ccr.Is_Referral__c = isReferral;            
            preventDuplicateOrganizationRelation(
                businessContactId,
                acc.PersonContactId,
                isReferral
            );

            insert ccr;

            return ccr.Id;
        

            } catch (AuraHandledException e) {
                throw e;
                } catch (Exception e) {
                throw new AuraHandledException(e.getMessage());
            }
    }


    @AuraEnabled(cacheable=false)
    public static Boolean hasExistingReferralCCR(Id relatedAccountId) {
        try {
            Account acc = [
                SELECT PersonContactId
                FROM Account
                WHERE Id = :relatedAccountId
                AND IsPersonAccount = true
                LIMIT 1
            ];

            if (acc.PersonContactId == null) return false;

            List<HealthCloudGA__ContactContactRelation__c> existing = [
                SELECT Id
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE HealthCloudGA__RelatedContact__c = :acc.PersonContactId
                AND Type__c = 'Business Contact'
                AND Is_Referral__c = true
                LIMIT 1
            ];

            return !existing.isEmpty();

        } catch (Exception e) {
            throw new AuraHandledException('Error checking referral CCR: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id createCallerCCR(
        Id callerContactId,
        Id relatedAccountId,
        String roleName,
        Boolean createAsCaller,
        String relationshipToClient,
        String familyRelationship,
        String otherRelationshipToClient
    ) {
        try {
            if (callerContactId == null) {
                throw new AuraHandledException('Contact is required.');
            }

            if (relatedAccountId == null) {
                throw new AuraHandledException('Related Account is required.');
            }

            if (String.isBlank(roleName)) {
                throw new AuraHandledException('Relationship selection is required.');
            }

            Account acc = [
                SELECT PersonContactId
                FROM Account
                WHERE Id = :relatedAccountId
                AND IsPersonAccount = true
                LIMIT 1
            ];

            if (acc.PersonContactId == null) {
                throw new AuraHandledException('Invalid Person Account.');
            }

            List<HealthCloudGA__ReciprocalRole__c> roleList = [
                SELECT Id, Name
                FROM HealthCloudGA__ReciprocalRole__c
                WHERE Name = :roleName
                LIMIT 1
            ];

            system.debug('roleList:'+roleList);

            if (roleList.isEmpty()) {
                throw new AuraHandledException('No Reciprocal Role found for: ' + roleName);
            }

            if (relationshipToClient == 'Family' && String.isBlank(familyRelationship)) {
                throw new AuraHandledException('Family Relationship is required.');
            }

            HealthCloudGA__ContactContactRelation__c ccr = new HealthCloudGA__ContactContactRelation__c();
            ccr.HealthCloudGA__Contact__c = callerContactId;
            ccr.HealthCloudGA__RelatedContact__c = acc.PersonContactId;
            ccr.HealthCloudGA__Role__c = roleList[0].Id;
            ccr.Type__c = (createAsCaller == true) ? CCR_TYPE_CALLER : CCR_TYPE_INDIVIDUAL;
            ccr.Relationship_to_Client__c = relationshipToClient;
            ccr.Family_Relationship__c = familyRelationship;
            ccr.Other_Relationship_to_Client__c = otherRelationshipToClient;                        
            preventDuplicateFamilyRelation(
                callerContactId,
                acc.PersonContactId
            );
		System.debug('CCR'+ccr);
            insert ccr;

            return ccr.Id;

        
        } catch (AuraHandledException e) {
            throw e;
            } catch (Exception e) {
                throw new AuraHandledException(e.getMessage());
            }
    }

    @AuraEnabled
    public static void deleteContactRelationship(String relationshipId) {
        try {
            
            
              if (!Schema.sObjectType.HealthCloudGA__ContactContactRelation__c.isDeletable()) {
            throw new AuraHandledException(
                'You do not have permission to delete this relationship.'
            );
        } 
            HealthCloudGA__ContactContactRelation__c ccr = [
                SELECT Id
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE Id = :relationshipId
                LIMIT 1
            ];

            delete ccr;

        } catch (Exception e) {
            throw new AuraHandledException('Error deleting relationship: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateFamilyCCR(
        Id     relationshipId,
        String roleName,
        String relationshipToClient,
        String familyRelationship,
        String otherRelationshipToClient
    ) {
        try {
            if (relationshipId == null) {
                throw new AuraHandledException('Relationship Id is required.');
            }
            if (String.isBlank(roleName)) {
                throw new AuraHandledException('Relationship selection is required.');
            }

            List<HealthCloudGA__ReciprocalRole__c> roleList = [
                SELECT Id FROM HealthCloudGA__ReciprocalRole__c
                WHERE Name = :roleName
                LIMIT 1
            ];

            if (roleList.isEmpty()) {
                throw new AuraHandledException('No Reciprocal Role found for: ' + roleName);
            }

            HealthCloudGA__ContactContactRelation__c ccr = [
                SELECT Id, HealthCloudGA__Role__c,
                    Relationship_to_Client__c,
                    Family_Relationship__c,
                    Other_Relationship_to_Client__c
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE Id = :relationshipId
                LIMIT 1
            ];

            ccr.HealthCloudGA__Role__c          = roleList[0].Id;
            ccr.Relationship_to_Client__c       = relationshipToClient;
            ccr.Family_Relationship__c          = familyRelationship;
            ccr.Other_Relationship_to_Client__c = otherRelationshipToClient;

            update ccr;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }



    @AuraEnabled
    public static void updateCoupleHouseholdCCR(
        Id relationshipId,
        Id roleId
    ) {
        try {
            if (relationshipId == null) {
                throw new AuraHandledException('Relationship Id is required.');
            }
            if (roleId == null) {
                throw new AuraHandledException('Role is required.');
            }

            HealthCloudGA__ContactContactRelation__c ccr = [
                SELECT Id, HealthCloudGA__Role__c
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE Id = :relationshipId
                LIMIT 1
            ];

            ccr.HealthCloudGA__Role__c = roleId;
            update ccr;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }



@AuraEnabled
public static void updateBusinessCCR(
    Id      relationshipId,
    Id      contactId,
    String  businessType,
    Boolean isReferral,
    Id      relatedAccountId
) {
    try {
        if (relationshipId == null) {
            throw new AuraHandledException('Relationship Id is required.');
        }
        if (String.isBlank(businessType)) {
            throw new AuraHandledException('Type is required.');
        }

        // 1. Find matching Reciprocal Role
        List<HealthCloudGA__ReciprocalRole__c> roleList = [
            SELECT Id FROM HealthCloudGA__ReciprocalRole__c
            WHERE Name = :businessType
            LIMIT 1
        ];

        if (roleList.isEmpty()) {
            throw new AuraHandledException(
                'No Reciprocal Role found matching the selected Type.'
            );
        }

        // 2. Update Contact.Type__c
        Contact c = new Contact(Id = contactId, ReferralType__c = businessType);
        update c;

        // 3. Update CCR
        HealthCloudGA__ContactContactRelation__c ccr = [
            SELECT Id, HealthCloudGA__Role__c, Is_Referral__c
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE Id = :relationshipId
            LIMIT 1
        ];

        ccr.HealthCloudGA__Role__c = roleList[0].Id;
        ccr.Is_Referral__c         = isReferral;
        update ccr;

    } catch (AuraHandledException e) {
        throw e;
    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}




    @AuraEnabled
    public static String saveAccountBypass(Account acc) {
        try {
            Database.DMLOptions dml = new Database.DMLOptions();
            // This is the specific setting to bypass alerts
            dml.DuplicateRuleHeader.allowSave = true;
            dml.DuplicateRuleHeader.runAsCurrentUser = true;

            // Use Database.insert instead of standard insert to apply DMLOptions
            Database.SaveResult sr = Database.insert(acc, dml);
            
            if (sr.isSuccess()) {
                return sr.getId();
            } else {
                throw new AuraHandledException(sr.getErrors()[0].getMessage());
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }




}