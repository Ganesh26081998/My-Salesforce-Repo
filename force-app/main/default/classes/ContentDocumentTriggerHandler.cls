/*
-----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : ContentDocumentTriggerHandler
CreatedOn      : 23-7-2026
LastModifiedOn : 8-12-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This trigger handler class manages ContentDocument-related
                    processing for Secondary Assessments, including handling
                    document and file operations associated with assessment
                    records and maintaining the required relationship between
                    uploaded files and their related assessment records.
-----------------------------------------------------------------------------
*/
public class ContentDocumentTriggerHandler {

    public static void handleBeforeDelete(Set<Id> documentIds) {

        System.debug('=== BEFORE DELETE ===');
        System.debug('Document Ids: ' + documentIds);

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
        ];

        System.debug('Links: ' + links);

        Set<Id> assessmentIds = new Set<Id>();

        for (ContentDocumentLink link : links) {

            System.debug('LinkedEntityId: ' + link.LinkedEntityId);

            if (link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() == SecondaryAssessment__c.SObjectType) {

                assessmentIds.add(link.LinkedEntityId);
            }
        }

        System.debug('Assessment Ids: ' + assessmentIds);

        if (assessmentIds.isEmpty()) {
            return;
        }

        List<SecondaryAssessment__c> assessments = new List<SecondaryAssessment__c>();

        for (Id assessmentId : assessmentIds) {
            assessments.add(new SecondaryAssessment__c(
                Id = assessmentId,
                PDF_Generated__c = false
            ));
        }

        System.debug('Updating: ' + assessments);

        if (!assessmentIds.isEmpty()) {
            update assessments;
        }

        System.debug('Update Complete');
    }
}