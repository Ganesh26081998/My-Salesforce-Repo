/*
----------------------------------------------------------------------------
Author        : Bhanu Prakash
Class Name    : OutboundReferralController
CreatedOn     : 18-01-2026
LastModifiedOn: 12-05-2026
LastModifiedBy: Bhanu Prakash
Description   : This class is used to manage outbound referrals by handling referral creation, patient and business account search, email validation, PDF generation, attachment handling, and automated referral email sending.




----------------------------------------------------------------------------
*/



public with sharing class OutboundReferralController {
    
    
    @AuraEnabled(cacheable=true)
    public static String getBusinessEmail(Id businessId) {
        if(businessId == null) return null;
        Account acc = [
            SELECT Id, Email__c
            FROM Account
            WHERE Id = :businessId
            LIMIT 1
        ];
        return acc.Email__c;
    }
    @AuraEnabled(cacheable=true)
    public static List<Account> searchBusinessAccounts(String searchKey) {
        String key = String.isBlank(searchKey) ? '%' : '%' + searchKey + '%';
        return [
            SELECT Id, Name
            FROM Account
            WHERE IsPersonAccount = false
            AND Name LIKE :key
            ORDER BY Name
            LIMIT 5
        ];
    }



    @AuraEnabled(cacheable=true)
    public static List<HealthCloudGA__ContactContactRelation__c> getPatientContacts(Id accountId) {
        if (accountId == null) {
            return new List<HealthCloudGA__ContactContactRelation__c>();
        }

        Account patientAccount = [
            SELECT PersonContactId
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (patientAccount.PersonContactId == null) {
            return new List<HealthCloudGA__ContactContactRelation__c>();
        }

        return [
            SELECT
                HealthCloudGA__RelatedContact__c,
                HealthCloudGA__Contact__c,
                HealthCloudGA__Contact__r.Name,
                HealthCloudGA__Contact__r.MobilePhone,
                HealthCloudGA__Contact__r.Email,
                HealthCloudGA__Role__r.Name
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE HealthCloudGA__RelatedContact__c = :patientAccount.PersonContactId
            AND HealthCloudGA__Contact__r.RecordType.DeveloperName = 'IndividualContact'
        ];
    }


    
    @AuraEnabled(cacheable=true)
    public static Account getPatientDetails(Id patientId) {
        if(patientId == null) return null;
        
        return [
            SELECT Id, Name,  PersonEmail, Date_Of_Birth__c,Mobile_Phones__c
            FROM Account
            WHERE Id = :patientId
            LIMIT 1
        ];
    }
    
    
    private static void validateAdditionalEmails(String emails) {
    if (String.isBlank(emails)) return;

    List<String> emailList = emails.split(',');

        if (emailList.size() > 3) {
            throw new AuraHandledException(
                'You can enter a maximum of 3 email addresses.'
            );
        }

        String emailRegex =
        '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';

        for (String email : emailList) {
            String trimmedEmail = email.trim();

            if (!Pattern.matches(emailRegex, trimmedEmail)) {
                throw new AuraHandledException(
                    'Invalid email format: ' + trimmedEmail
                );
            }
        }
    }

    
    
    @AuraEnabled
    public static Id saveReferral(
        Id businessAccountId,
        Id patientAccountId,
        String referralType,
        String businessEmail,
        String additionalEmails,
        String referralReason,
        String role,
        Id contact,
        Id referralRecordTypeId
    ) {
        if(businessAccountId == null || patientAccountId == null){
            throw new AuraHandledException('Business and Patient are required.');
        }
        if (referralRecordTypeId == null) {
        throw new AuraHandledException('Referral Record Type is required.');
    	}
        
        // if(referralType == 'Home Care Agency' && String.isBlank(additionalEmails)) {
        //     throw new AuraHandledException(
        //         'Additional Email Addresses are required for Home Care Agency referrals.'
        //     );
        // }
        
         validateAdditionalEmails(additionalEmails);
        
        map<Id,Account> newmap = new map<Id,Account>([Select Id, Name From Account where Id=:businessAccountId or Id=:patientAccountId]);
        
        String baName = newmap.get(businessAccountId).Name;
        String paName = newmap.get(patientAccountId).Name;
        
        
        Referral__c ref = new Referral__c();
        ref.Name= 'Referred To'+' '+ baName;
        ref.RecordTypeId = referralRecordTypeId;
        ref.Business_Account__c = businessAccountId;
        ref.Patient__c = patientAccountId;
        ref.Referral_Type__c = referralType;
        ref.Business_Email__c = businessEmail;
        ref.Additional_Email_Addresses__c = additionalEmails;
        ref.Reason_for_Referral__c = referralReason;
        ref.Role__c = role;
        ref.Contact_Lookup__c = contact;
        system.debug('refcontact:'+ref.Contact_Lookup__c);


        
        List<Referral__c> existingRefs = [
            SELECT Id
            FROM Referral__c
            WHERE Business_Account__c = :businessAccountId
            AND Patient__c = :patientAccountId
            AND RecordTypeId = :referralRecordTypeId
            LIMIT 1
        ];

        if (!existingRefs.isEmpty()) {
            throw new AuraHandledException(
                'A referral already exists for this Business Account and Client.'
            );
        }
        
        insert ref;
              
        
        if (!String.isBlank(referralReason)) {
            String rewrittenReason = extractAndSaveImages(referralReason, ref.Id);
            if (rewrittenReason != referralReason) {
                ref.Reason_for_Referral__c = rewrittenReason;
                update ref;
            }
        }

        
        generateReferralPDFAsync(ref.Id);   
        return ref.Id;
    }
    
    @future(callout=true)
    public static void generateReferralPDFAsync(Id referralId) {
        
        
        Blob pdfBlob = generateReferralPDFAttachment(referralId);
        
        try {
            
            Referral__c ref = [
                SELECT Id, Name, Business_Email__c,Additional_Email_Addresses__c, Referral_Type__c
                FROM Referral__c
                WHERE Id = :referralId
                LIMIT 1
            ];

             if(String.isBlank(ref.Referral_Type__c)){
                return;
            }

            List<String> toAddresses = new List<String>();

            if (!String.isBlank(ref.Business_Email__c)) {
                toAddresses.add(ref.Business_Email__c.trim());
            }
            
            
            if (!String.isBlank(ref.Additional_Email_Addresses__c)) {
                for (String email : ref.Additional_Email_Addresses__c.split(',')) {
                    if (!String.isBlank(email)) {
                        toAddresses.add(email.trim());
                    }
                }
            }
            system.debug('toaddress'+toAddresses);
            
            if (toAddresses.isEmpty()) {
                return; 
            }
          
           
            // WellSky_Outbound_Referral_Emails__mdt metadataRecord;

            // for(WellSky_Outbound_Referral_Emails__mdt m :
            //     WellSky_Outbound_Referral_Emails__mdt.getAll().values()) {

            //     if(m.Referral_Type__c == ref.Referral_Type__c) {
            //         metadataRecord = m;
            //         break;
            //     }
            // }

            

            // if(metadataRecord!= null && metadataRecord.Email__c != null){
            //     toAddresses.add(metadataRecord.Email__c);
            // }        

            
            OrgWideEmailAddress owea = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE IsAllowAllProfiles = true
                LIMIT 1
            ];

            if(owea == null){
                return;
            }

            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

            mail.setToAddresses(toAddresses);
            mail.setTemplateId(getEmailTemplateId());
            mail.setTargetObjectId(UserInfo.getUserId());
            mail.setOrgWideEmailAddressId(owea.Id);
            mail.setSaveAsActivity(false);

            
            Messaging.EmailFileAttachment attachment =
                new Messaging.EmailFileAttachment();

            attachment.setFileName('Outbound Referral.pdf');
            attachment.setBody(pdfBlob);
            attachment.setContentType('application/pdf');

            mail.setFileAttachments(
                new Messaging.EmailFileAttachment[] { attachment }
            );                        
                
                
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
                
            } catch(Exception ex) {
                System.debug('Error sending referral email: ' + ex.getMessage());
            }
    }
    private static Id getEmailTemplateId() {
        EmailTemplate et = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :System.Label.OutboundReferralEmailTemplate
            LIMIT 1
        ];
        return et.Id;
    }
    
    
    
    private static  Blob generateReferralPDFAttachment(Id referralId) {
        
        PageReference pdfPage = Page.OutboundReferralPDF;
        pdfPage.getParameters().put('id', referralId);
        
        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('Test PDF')
            : pdfPage.getContentAsPDF();
        
        Attachment att = new Attachment();
        att.ParentId = referralId;
        att.Name = 'Outbound Referral.pdf';
        att.Body = pdfBlob;
        att.ContentType = 'application/pdf';
        
        insert att;
        
        return pdfBlob;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchKey,Boolean ispersonAccount) {
        
        String key = String.isBlank(searchKey) ? '%' : '%' + searchKey + '%';
        
        return [
            SELECT Id, Name
            FROM Account
            WHERE IsPersonAccount= :ispersonAccount And Name LIKE :key
            ORDER BY Name
            LIMIT 50
        ];
    }
       
    
    @AuraEnabled(cacheable=true)
    public static List<String> getReferralTypePicklist() {
        List<Schema.PicklistEntry> entries = 
            Schema.SObjectType.Referral__c.fields.Referral_Type__c.getPicklistValues();
        List<String> values = new List<String>();
        for(Schema.PicklistEntry e : entries){
            if(e.isActive()) {  
                values.add(e.getValue());
            }
        }
        return values;
    }

    @AuraEnabled(cacheable=true)
    public static String getBusinessReferralType(Id accountId) {

        if(accountId == null){
            return null;
        }

        Account acc = [
            SELECT Referral_Type__c, Referral_Source_Type__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        return acc.Referral_Source_Type__c;
    }


    private static String extractAndSaveImages(String richText, Id parentId) {
        if (String.isBlank(richText) || parentId == null) return richText;

        Pattern imgPattern = Pattern.compile(
            '(?i)<img([^>]*)src="data:([^;]+);base64,([^"]+)"([^>]*)/?>'
        );
        Matcher m = imgPattern.matcher(richText);

        
        List<Map<String, String>> matches = new List<Map<String, String>>();

        while (m.find()) {
            Map<String, String> matchInfo = new Map<String, String>();
            matchInfo.put('fullMatch', m.group(0));
            matchInfo.put('mimeType',  m.group(2));
            matchInfo.put('b64Data',   m.group(3));
            matches.add(matchInfo);
        }

        if (matches.isEmpty()) return richText;

        
        List<Attachment> attsToInsert = new List<Attachment>();

        for (Map<String, String> matchInfo : matches) {
            String mimeType = matchInfo.get('mimeType');
            String b64Data  = matchInfo.get('b64Data');

            String ext = mimeType.containsIgnoreCase('png')  ? 'png'
                    : mimeType.containsIgnoreCase('jpeg') ? 'jpg'
                    : mimeType.containsIgnoreCase('jpg')  ? 'jpg'
                    : mimeType.containsIgnoreCase('gif')  ? 'gif'
                    : mimeType.containsIgnoreCase('webp') ? 'webp'
                    : 'png';

            Attachment att = new Attachment();
            att.ParentId    = parentId;
            att.Name        = 'referral_image_' + attsToInsert.size() + '.' + ext;
            att.ContentType = mimeType;
            att.Body        = EncodingUtil.base64Decode(b64Data);
            attsToInsert.add(att);
        }

        insert attsToInsert;

        String result = richText;

        for (Integer i = 0; i < matches.size(); i++) {
            String fullMatch = matches.get(i).get('fullMatch');
            String servletUrl = '/servlet/servlet.FileDownload?file=' + attsToInsert.get(i).Id;
            String replacement = '<img src="' + servletUrl + '" style="max-width:100%;height:auto;"/>';

            Integer idx = result.indexOf(fullMatch);
            if (idx >= 0) {
                result = result.substring(0, idx) 
                    + replacement 
                    + result.substring(idx + fullMatch.length());
            }
        }

        return result;
    }
    
    
}