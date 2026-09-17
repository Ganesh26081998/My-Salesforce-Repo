/*
----------------------------------------------------------------------------
Author        : Prasad Patil
Class Name    : WellSpringHospitalizationController
CreatedOn     : 13-03-2026
LastModifiedOn: 18-05-2026
LastModifiedBy: Prasad Patil
Description   : This class is used for create a hospitalization record on Active Client and store in the Custom object.
----------------------------------------------------------------------------
*/

public with sharing class WellSpringHospitalizationController {
    @AuraEnabled(cacheable=true)
    public static List<Hospitalization__c> getHospitalizations(Id accountId) {
        if (accountId == null) {
            return new List<Hospitalization__c>();
        }

        return [
            SELECT
                Id,
                Name,
                Account__c,
                Hospitalization_Status__c,
                Admission_Type__c,
                Admission_Date__c,
                Hospital_Name__c,
                Primary_diagnosis__c,
                Discharge_Date__c,
                Role_during_hospitalization__c,
                Reason_for_admission__c,
                Current_Hospitalization__c,
                CreatedDate
            FROM Hospitalization__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static void deleteHospitalization(Id hospitalizationId) {
        if (hospitalizationId == null) {
            throw new AuraHandledException('Hospitalization record Id is required.');
        }

        if (!Schema.sObjectType.Hospitalization__c.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete hospitalization records.');
        }

        List<Hospitalization__c> hospitalizations = [
            SELECT Id
            FROM Hospitalization__c
            WHERE Id = :hospitalizationId
            LIMIT 1
        ];

        if (hospitalizations.isEmpty()) {
            throw new AuraHandledException('Hospitalization record not found.');
        }

        try {
            delete hospitalizations[0];
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }
}