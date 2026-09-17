/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : AccountStageHistoryController
CreatedOn      : 23-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This controller class is used to fetch Account stage history
                 details and return formatted stage transition dates for UI
                 display purposes.
----------------------------------------------------------------------------
*/

public with sharing class AccountStageHistoryController {

    private static final String DATE_FORMAT = 'MM/dd/yyyy';

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getStageHistory(Id accountId) {

        Account acc = [
            SELECT
                Account_Status__c,
                CreatedDate,
                NewInquiryDate__c,
                OutreachInprogressDate__c,
                ProspectDate__c,
                AssessmentScheduledStageDate__c,
                AssessmentCompletedStageDate__c,
                ClientDate__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        Map<String, String> historyMap = new Map<String, String>();

        historyMap.put(
            'New Inquiry',
            formatDate(acc.NewInquiryDate__c)
        );

        historyMap.put(
            'Outreach In Progress',
            formatDate(acc.OutreachInprogressDate__c)
        );

        historyMap.put(
            'Prospect',
            formatDate(acc.ProspectDate__c)
        );

        historyMap.put(
            'Assessment Scheduled',
            formatDate(acc.AssessmentScheduledStageDate__c)
        );

        historyMap.put(
            'Assessment Completed Stage',
            formatDate(acc.AssessmentCompletedStageDate__c)
        );

        historyMap.put(
            'Client',
            formatDate(acc.ClientDate__c)
        );

        return new Map<String, Object>{
            'history' => historyMap,
            'createdDate' => String.valueOf(acc.CreatedDate.date())
        };
    }

     private static String formatDate(Date dt) {

        if (dt == null) {
            return null;
        }

        return Datetime.newInstance(
            dt,
            Time.newInstance(0, 0, 0, 0)
        ).format(DATE_FORMAT);
    }
}