public with sharing class CCRTriggerHandler {

    public static void handleAfterDelete(
        List<HealthCloudGA__ContactContactRelation__c> oldList
    ) {

        // ✅ Contact Record Type Id (Business Contact)
        Id contactBusinessRtId = Schema.SObjectType.Contact
            .getRecordTypeInfosByName()
            .get('Business Contact')
            .getRecordTypeId();

        // ✅ Referral Record Type Id (Inbound)
        Id inboundReferralRtId = Schema.SObjectType.Referral__c
            .getRecordTypeInfosByName()
            .get('Inbound')
            .getRecordTypeId();

        // ✅ Collect Contact & Related Contact Ids
        Set<Id> contactIds = new Set<Id>();
        Set<Id> relatedContactIds = new Set<Id>();

        for (HealthCloudGA__ContactContactRelation__c ccr : oldList) {
            if (
                ccr.Is_Referral__c &&
                ccr.HealthCloudGA__Contact__c != null &&
                ccr.HealthCloudGA__RelatedContact__c != null
            ) {
                contactIds.add(ccr.HealthCloudGA__Contact__c);
                relatedContactIds.add(ccr.HealthCloudGA__RelatedContact__c);
            }
        }

        if (contactIds.isEmpty()) return;

        // ✅ Query Contacts (to validate Record Type)
        Map<Id, Contact> contactMap = new Map<Id, Contact>(
            [SELECT Id, RecordTypeId FROM Contact WHERE Id IN :contactIds]
        );

        // ✅ Filter only Business Contacts
        Set<Id> validContactIds = new Set<Id>();

        for (Id conId : contactMap.keySet()) {
            if (contactMap.get(conId).RecordTypeId == contactBusinessRtId) {
                validContactIds.add(conId);
            }
        }

        if (validContactIds.isEmpty()) return;

        // ✅ Get AccountIds from Related Contacts (Person Accounts)
        Map<Id, Id> relatedContactToAccountMap = new Map<Id, Id>();

        for (Contact con : [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id IN :relatedContactIds
        ]) {
            if (con.AccountId != null) {
                relatedContactToAccountMap.put(con.Id, con.AccountId);
            }
        }

        if (relatedContactToAccountMap.isEmpty()) return;

        // ✅ Build Contact → Related Contact map (ONLY valid contacts)
        Map<Id, Id> contactToRelatedContactMap = new Map<Id, Id>();

        for (HealthCloudGA__ContactContactRelation__c ccr : oldList) {
            if (
                ccr.Is_Referral__c &&
                validContactIds.contains(ccr.HealthCloudGA__Contact__c) &&
                relatedContactToAccountMap.containsKey(ccr.HealthCloudGA__RelatedContact__c)
            ) {
                contactToRelatedContactMap.put(
                    ccr.HealthCloudGA__Contact__c,
                    ccr.HealthCloudGA__RelatedContact__c
                );
            }
        }

        if (contactToRelatedContactMap.isEmpty()) return;

        Set<Id> patientAccountIds = new Set<Id>(relatedContactToAccountMap.values());

        // ✅ Query Referral
        List<Referral__c> referralList = [
            SELECT Id, Contact_Lookup__c, Patient__c
            FROM Referral__c
            WHERE Contact_Lookup__c IN :validContactIds
            AND Patient__c IN :patientAccountIds
            AND RecordTypeId = :inboundReferralRtId
        ];

        if (referralList.isEmpty()) return;

        // ✅ Strict match
        List<Referral__c> referralsToDelete = new List<Referral__c>();

        for (Referral__c ref : referralList) {

    if (!contactToRelatedContactMap.containsKey(ref.Contact_Lookup__c)) {
        continue;
    }

    Id relatedContactId = contactToRelatedContactMap.get(ref.Contact_Lookup__c);

    if (relatedContactId == null) {
        continue;
    }

    if (!relatedContactToAccountMap.containsKey(relatedContactId)) {
        continue;
    }

    Id expectedAccountId = relatedContactToAccountMap.get(relatedContactId);

    if (expectedAccountId != null && ref.Patient__c == expectedAccountId) {
        referralsToDelete.add(ref);
    }
}

        // ✅ Delete
        if (!referralsToDelete.isEmpty()) {
            delete referralsToDelete;
        }
    }
}