/*
----------------------------------------------------------------------------
Author        : Bhanu Prakash
Class Name    : OutboundReferralPDFController
CreatedOn     : 18-01-2026
LastModifiedOn: 12-05-2026
LastModifiedBy: Bhanu Prakash
Description   : This controller is used to fetch and format outbound referral, patient, and related contact details for generating the Outbound Referral PDF document.


----------------------------------------------------------------------------
*/





public with sharing class OutboundReferralPDFController {

    public Referral__c referral { get; private set; }
    public List<AccountContactRelation> relatedContacts { get; private set; }

    public String formattedReason {
        get {
            if (referral == null || String.isBlank(referral.Reason_for_Referral__c)) {
                return '';
            }

            String val = referral.Reason_for_Referral__c;

            val = val.replaceAll(
                '(?i)<img([^>]*)src="data:[^"]*"([^>]*)/?>',
                ''
            );

            val = val.replaceAll('(?is)<style.*?</style>', '');
            val = val.replaceAll('(?is)<script.*?</script>', '');

            val = val.replaceAll('(?i)\\sstyle="[^"]*"', '');
            val = val.replaceAll('(?i)\\sclass="[^"]*"', '');

            val = val.replaceAll(
                '(?i)</?(div|span|font|section|article)[^>]*>',
                ''
            );

            return val;
        }
    }

    public String createdDateOnly {
    get {
        if (referral == null || referral.CreatedDate == null) {
            return '';
        }
        return referral.CreatedDate.date().format();
    }
}


    public OutboundReferralPDFController(ApexPages.StandardController sc) {

        Id referralId = sc.getId();

        if (referralId == null) {
            referral = new Referral__c();
            relatedContacts = new List<AccountContactRelation>();
            return;
        }

        referral = [
            SELECT
                Id,
                Patient__c,
                Referral_Type__c,
                Business_Email__c,
                Role__c,
                Contact_Lookup__r.Name,
                Contact_Lookup__r.HomePhone,
                Contact_Lookup__r.MobilePhone,
                Contact_Lookup__r.Email,
                Additional_Email_Addresses__c,
                Reason_for_Referral__c,
                Business_Account__r.Name,
                Patient__r.Name,
                Patient__r.Mobile_Phones__c,
                Patient__r.Date_Of_Birth__c,
                Patient__r.PersonEmail,
                CreatedDate
            FROM Referral__c
            WHERE Id = :referralId
            LIMIT 1
        ];

        relatedContacts = new List<AccountContactRelation>();

        if (referral.Patient__c != null) {
            relatedContacts = [
                SELECT
                    Contact.Name,
                    Roles
                FROM AccountContactRelation
                WHERE AccountId = :referral.Patient__c
                AND IsActive = true
                AND ContactId != null
            ];
        }
    }
}