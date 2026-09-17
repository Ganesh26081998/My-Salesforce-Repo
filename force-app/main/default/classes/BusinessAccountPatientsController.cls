public without sharing class BusinessAccountPatientsController {

    public class PatientRecord {
        @AuraEnabled public String orgName;
        @AuraEnabled public Id patientId;
        @AuraEnabled public String patientName;
        @AuraEnabled public String accountStatus;
        @AuraEnabled public String phone;
        @AuraEnabled public String businessContactNames; // comma-separated, de-duped
    }

    @AuraEnabled(cacheable=true)
    public static List<PatientRecord> getPatients(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required');
        }

        try {

            String orgName;
            Set<Id> contactIds = new Set<Id>();

            // If component is on Account record page
            if (recordId.getSObjectType() == Account.SObjectType) {

                Account bizAccount = [
                    SELECT Id, Name
                    FROM Account
                    WHERE Id = :recordId
                    LIMIT 1
                ];

                orgName = bizAccount.Name;

                for (Contact con : [
                    SELECT Id
                    FROM Contact
                    WHERE AccountId = :recordId
                ]) {
                    contactIds.add(con.Id);
                }
            }
            // If component is on Contact record page
            else if (recordId.getSObjectType() == Contact.SObjectType) {

                Contact businessContact = [
                    SELECT Id, Name, Account.Name
                    FROM Contact
                    WHERE Id = :recordId
                    LIMIT 1
                ];

                orgName = businessContact.Account != null
                    ? businessContact.Account.Name
                    : '';

                // Only this contact
                contactIds.add(recordId);
            }

            if (contactIds.isEmpty()) {
                return new List<PatientRecord>();
            }

            List<HealthCloudGA__ContactContactRelation__c> ccrs = [
                SELECT
                    HealthCloudGA__Contact__r.Name,
                    HealthCloudGA__RelatedContact__r.AccountId,
                    HealthCloudGA__RelatedContact__r.Account.Name,
                    HealthCloudGA__RelatedContact__r.Account.Account_Status__c,
                    HealthCloudGA__RelatedContact__r.Account.Mobile_Phones__c,
                    HealthCloudGA__RelatedContact__r.Account.IsPersonAccount
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE HealthCloudGA__Contact__c IN :contactIds
                AND Is_Referral__c = true ORDER BY CreatedDate DESC
            ];

            // Deduplicate by patient — merge all unique business contact names per patient
            Map<Id, PatientRecord> patientMap = new Map<Id, PatientRecord>();
            Map<Id, Set<String>> contactNameMap = new Map<Id, Set<String>>();

            for (HealthCloudGA__ContactContactRelation__c ccr : ccrs) {

                Id pid = ccr.HealthCloudGA__RelatedContact__r.AccountId;

                if (pid == null ||
                    !ccr.HealthCloudGA__RelatedContact__r.Account.IsPersonAccount) {
                    continue;
                }

                if (!patientMap.containsKey(pid)) {

                    PatientRecord pr = new PatientRecord();
                    pr.orgName = orgName;
                    pr.patientId = pid;
                    pr.patientName = ccr.HealthCloudGA__RelatedContact__r.Account.Name;
                    pr.accountStatus = ccr.HealthCloudGA__RelatedContact__r.Account.Account_Status__c;
                    pr.phone = ccr.HealthCloudGA__RelatedContact__r.Account.Mobile_Phones__c;

                    patientMap.put(pid, pr);
                    contactNameMap.put(pid, new Set<String>());
                }

                String contactName = ccr.HealthCloudGA__Contact__r.Name;
                if (String.isNotBlank(contactName)) {
                    contactNameMap.get(pid).add(contactName);
                }
            }

            // Attach merged contact names to each patient record
            List<PatientRecord> patients = new List<PatientRecord>();

            for (Id pid : patientMap.keySet()) {

                PatientRecord pr = patientMap.get(pid);

                pr.businessContactNames = String.join(
                    new List<String>(contactNameMap.get(pid)),
                    ', '
                );

                patients.add(pr);
            }

            return patients;

        } catch (Exception e) {
            throw new AuraHandledException(
                'Error retrieving patients: ' + e.getMessage()
            );
        }
    }
}