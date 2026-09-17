/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : InactiveContactsBatch
CreatedOn      : 02-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This batch class is used to identify inactive Contacts under
                 Business Accounts based on configured activity thresholds.
                 It checks Tasks, Events, and Email interactions, groups
                 inactive Contacts by Account Owner, and sends notification
                 emails using configured email templates.
----------------------------------------------------------------------------
*/
global class InactiveContactsBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    private Integer daysThreshold;
    private String  templateDeveloperName;    
    
    global Map<Id, Map<String, List<String>>> ownerToAccountContactsMap;
    global Map<Id, String> ownerEmailMap;
    global Map<Id, String> ownerNameMap;

    global InactiveContactsBatch() {
        ownerToAccountContactsMap = new Map<Id, Map<String, List<String>>>();
        ownerEmailMap             = new Map<Id, String>();
        ownerNameMap              = new Map<Id, String>();

        Inactive_Contact_Config__mdt config = [
            SELECT Days_Threshold__c,
                   Email_Template_Name__c                   
            FROM   Inactive_Contact_Config__mdt
            WHERE  DeveloperName = 'InactiveContactConfig'
            LIMIT  1
        ];

        this.daysThreshold         = Integer.valueOf(config.Days_Threshold__c);
        this.templateDeveloperName = config.Email_Template_Name__c;
		
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, OwnerId,
                   Owner.Email, Owner.Name, Owner.IsActive,
                   (SELECT Id, Name FROM Contacts WHERE RecordType.DeveloperName = 'IndustriesBusiness')
            FROM   Account
            WHERE  Owner.IsActive = TRUE
			AND RecordType.DeveloperName = 'Business_Account'
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Account> accounts) {

        Date cutoffDate = Date.today().addDays(-daysThreshold);
        
        List<Id> allContactIds = new List<Id>();
        for (Account acc : accounts) {
            for (Contact con : acc.Contacts) {
                allContactIds.add(con.Id);
            }
        }
        if (allContactIds.isEmpty()) return;

        
        Set<Id> activeContactIds = new Set<Id>();

    
        for (Task t : [
            SELECT WhoId FROM Task
            WHERE  WhoId        IN :allContactIds
              AND  ActivityDate >= :cutoffDate
        ]) {
            activeContactIds.add(t.WhoId);
        }
        
        for (Event e : [
            SELECT WhoId FROM Event
            WHERE  WhoId        IN :allContactIds
              AND  ActivityDate >= :cutoffDate
        ]) {
            activeContactIds.add(e.WhoId);
        }
    
        for (EmailMessageRelation emr : [
            SELECT RelationId FROM EmailMessageRelation
            WHERE  RelationId              IN :allContactIds
              AND  EmailMessage.MessageDate >= :cutoffDate
        ]) {
            activeContactIds.add(emr.RelationId);
        }

        for (Account acc : accounts) {

            List<String> inactiveNames = new List<String>();
            for (Contact con : acc.Contacts) {
                if (!activeContactIds.contains(con.Id)) {
                    inactiveNames.add(con.Name);
                }
            }
            if (inactiveNames.isEmpty()) continue;

            Id ownerId = acc.OwnerId;
            if (!ownerToAccountContactsMap.containsKey(ownerId)) {
                ownerToAccountContactsMap.put(ownerId, new Map<String, List<String>>());
                ownerEmailMap.put(ownerId, acc.Owner.Email);
                ownerNameMap.put(ownerId, acc.Owner.Name);
            }
            ownerToAccountContactsMap.get(ownerId).put(acc.Name, inactiveNames);
        }
    }


    global void finish(Database.BatchableContext bc) {

        if (ownerToAccountContactsMap.isEmpty()) return;

        EmailTemplate template = [
            SELECT Id, Subject, Body, HtmlValue
            FROM   EmailTemplate
            WHERE  DeveloperName = :templateDeveloperName
            LIMIT  1
        ];
        
        Id oweaId = null;
        
            List<OrgWideEmailAddress> oweaList = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE IsAllowAllProfiles = true
                LIMIT  1
            ];
            if (!oweaList.isEmpty()) {
                oweaId = oweaList[0].Id;
            }
        

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id ownerId : ownerToAccountContactsMap.keySet()) {

            String ownerEmail = ownerEmailMap.get(ownerId);
            String ownerName  = ownerNameMap.get(ownerId);
            if (String.isBlank(ownerEmail)) continue;

            Map<String, List<String>> accountContactsMap = ownerToAccountContactsMap.get(ownerId);
        
            String bodyContent = buildBodyContent(accountContactsMap);
            String htmlContent = buildHtmlContent(accountContactsMap);
            
            String finalSubject = template.Subject
                .replace('{!DAYS_THRESHOLD}', String.valueOf(daysThreshold));

            String finalPlainBody = template.Body
                .replace('{!recipient.Name}',  ownerName)
                .replace('{!DAYS_THRESHOLD}',  String.valueOf(daysThreshold))
                .replace('{!BODY_CONTENT}',    bodyContent);

            String finalHtmlBody = '';
            if (String.isNotBlank(template.HtmlValue)) {
                finalHtmlBody = template.HtmlValue
                    .replace('{!recipient.Name}', ownerName)
                    .replace('{!DAYS_THRESHOLD}', String.valueOf(daysThreshold))
                    .replace('{!BODY_CONTENT}',   htmlContent);
            }
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ ownerEmail });
            mail.setSubject(finalSubject);
            mail.setPlainTextBody(finalPlainBody);
            if (String.isNotBlank(finalHtmlBody)) {
                mail.setHtmlBody(finalHtmlBody);
            }
            if (oweaId != null) {
                mail.setOrgWideEmailAddressId(oweaId);
            }
            mail.setSaveAsActivity(false);

            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }


    private String buildBodyContent(Map<String, List<String>> accountContactsMap) {
		String content = '';
		Integer accountNum = 1;

		for (String accountName : accountContactsMap.keySet()) {
			content += accountNum + '. Account - ' + accountName + '\n';			
			for (String contactName : accountContactsMap.get(accountName)) {
				content += '    ' + 'Contact - ' + contactName + '\n';				
			}
			content += '\n';
			accountNum++;
		}
		return content;
	}

	private String buildHtmlContent(Map<String, List<String>> accountContactsMap) {
		String html = '<table style="border-collapse:collapse; width:100%;">';
		Integer accountNum = 1;

		for (String accountName : accountContactsMap.keySet()) {
			html += '<tr style="background:#f0f4ff;">'
				+ '<td style="padding:8px; border:1px solid #ccc;">'
				+'<b>'+accountNum+'. ' + 'Account '  + ' -</b> ' + accountName
				+ '</td></tr>';
			
			for (String contactName : accountContactsMap.get(accountName)) {
				html += '<tr><td style="padding:6px 24px; border:1px solid #ccc;">'
					+ '<b>Contact ' + ' -</b> ' + contactName
					+ '</td></tr>';				
			}
			accountNum++;
		}

		html += '</table>';
		return html;
	}
	
}