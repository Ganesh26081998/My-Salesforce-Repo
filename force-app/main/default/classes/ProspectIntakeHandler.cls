/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : ProspectIntakeHandler
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : It ensures new website prospects are instantly assigned to the correct 
                user and immediately alerts that user via email so they can take action.
----------------------------------------------------------------------------
*/

public class ProspectIntakeHandler {

    public static void handleBeforeInsert(List<Account> newAccounts) {
        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();

        Intake_Coordinator_Config__mdt config = Intake_Coordinator_Config__mdt.getInstance('Default');

        if (config == null || String.isBlank(config.Intake_User_Id__c)) {
            return;
        }

        Id intakeUserId = config.Intake_User_Id__c;

        for (Account acc : newAccounts) {
           if (acc.RecordTypeId == prospectRtId && 
                acc.Prospect_Source__c == 'Website') {
                acc.OwnerId = intakeUserId;
            }
        }
    }

    public static void handleAfterInsert(List<Account> newAccounts) {
        Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();

        Set<Id> prospectIds = new Set<Id>();

        for (Account acc : newAccounts) {
            if (acc.RecordTypeId == prospectRtId) {
                prospectIds.add(acc.Id);
            }
        }

        if (prospectIds.isEmpty()) {
            return;
        }

        Intake_Coordinator_Config__mdt config = Intake_Coordinator_Config__mdt.getInstance('Default');
        if (config == null || String.isBlank(config.Intake_User_Id__c)) {
            return;
        }

        List<Account> prospectsWithData = [
            SELECT Id, 
                   Name, 
                   Mobile_Phones__c, 
                   PersonEmail, 
                   Prospect_Source__c,
                   Location_g__c
            FROM Account 
            WHERE Id IN :prospectIds
        ];

        sendEmailToIntakeUser(prospectsWithData, config.Intake_User_Id__c);
    }
	@TestVisible
    private static void sendEmailToIntakeUser(List<Account> prospects, Id intakeUserId) {
        
        User intakeUser = [
            SELECT Id, Email, FirstName 
            FROM User 
            WHERE Id = :intakeUserId AND IsActive = true 
            LIMIT 1
        ];
        
        OrgWideEmailAddress owea;
        try {
            owea = [SELECT Id FROM OrgWideEmailAddress WHERE IsAllowAllProfiles = true LIMIT 1];
        } catch (Exception e) {
            System.debug('No OrgWideEmailAddress found: ' + e.getMessage());
        }

        if (String.isBlank(intakeUser.Email)) return;

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        for (Account acc : prospects) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

            email.setToAddresses(new String[] { intakeUser.Email });
            if (owea != null) email.setOrgWideEmailAddressId(owea.Id);
            
            email.setSubject('New Prospect Assigned to You: ' + acc.Name);

            String emailVal = (acc.PersonEmail != null) ? acc.PersonEmail : 'N/A';
            String phoneVal = (acc.Mobile_Phones__c != null) ? acc.Mobile_Phones__c : 'N/A';
            String sourceVal = (acc.Prospect_Source__c != null) ? acc.Prospect_Source__c : 'N/A';
            String locationVal = (acc.Location_g__c != null) ? acc.Location_g__c : 'N/A';

            // Build HTML email with clickable link
            String prospectUrl = baseUrl + '/' + acc.Id;
            
            String htmlBody = '<html><body style="font-family: Arial, sans-serif; color: #333;">' +
                '<p>Hello ' + intakeUser.FirstName + ',</p>' +
                '<p>A new Prospect has been created and assigned to you for intake follow-up.</p>' +
                '<p><strong>Prospect Details:</strong></p>' +
                '<ul>' +
                '<li><strong>Name:</strong> ' + acc.Name + '</li>' +
                '<li><strong>Phone:</strong> ' + phoneVal + '</li>' +
                '<li><strong>Email:</strong> ' + emailVal + '</li>' +
                '<li><strong>Prospect Source:</strong> ' + sourceVal + '</li>' +
                '<li><strong>Location:</strong> ' + locationVal + '</li>' +
                '</ul>' +
                '<p><a href="' + prospectUrl + '" style="background-color: #0070d2; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block; font-weight: bold;">Open Prospect Record</a></p>' +
                '<p>Thank you.</p>' +
                '</body></html>';
            
            email.setHtmlBody(htmlBody);

            emails.add(email);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(emails);
                
                // SIMPLIFIED: Collect failures for logging (without Email_Delivery_Status__c)
                /* List<Email_Failure_Log__c> failureLogs = new List<Email_Failure_Log__c>(); */
                
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        String errorMsg = 'Email failed for Prospect ID: ' + prospects[i].Id + ' - ';
                        for (Messaging.SendEmailError error : results[i].getErrors()) {
                            errorMsg += error.getMessage();
                        }
                        System.debug(LoggingLevel.ERROR, errorMsg);
                        
                        /*
                        // SIMPLIFIED: Create error log entry WITHOUT Email_Delivery_Status__c
                        Email_Failure_Log__c failureLog = new Email_Failure_Log__c();
                        failureLog.Prospect_ID__c = prospects[i].Id;
                        failureLog.Prospect_Name__c = prospects[i].Name;
                        failureLog.Error_Message__c = errorMsg;
                        failureLog.Intake_User_Email__c = intakeUser.Email;
                        failureLog.Notes_for_Follow_up__c = 'Email delivery failed. Please review error message and resend if needed.';
                        
                        failureLogs.add(failureLog);
                        */
                    }
                }
                
                /*
                // Insert all failure logs
                if (!failureLogs.isEmpty()) {
                    try {
                        insert failureLogs;
                        System.debug('Inserted ' + failureLogs.size() + ' error log entries');
                    } catch (DmlException e) {
                        System.debug(LoggingLevel.ERROR, 'Error inserting failure logs: ' + e.getMessage());
                    }
                }
                */
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Exception sending emails: ' + e.getMessage());
            }
        }
    }
}