public with sharing class WellSkyRelationshipHandler {

    // ── @TestVisible flags & overrides ─────────────────────────────────
    @TestVisible private static Boolean skipPerformSync   = false;
    @TestVisible private static Boolean skipEmailSend     = false;
    // Injected config for tests (bypasses getInstance which needs real CMT)
    @TestVisible private static String  testFieldsToCopy  = null;
    // ───────────────────────────────────────────────────────────────────

    @AuraEnabled
    public static void manualSync(Id recordId) {

        if (recordId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :recordId
        ];

        if (contacts.isEmpty()) {
            throw new AuraHandledException(
                'No contact is linked to this account.');
        }

        Set<Id> contactIds = new Set<Id>();
        for (Contact c : contacts) {
            contactIds.add(c.Id);
        }

        List<HealthCloudGA__ContactContactRelation__c> relations = [
            SELECT Id
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE Relationship_Status__c = 'Related'
            AND (
                HealthCloudGA__Contact__c IN :contactIds
                OR
                HealthCloudGA__RelatedContact__c IN :contactIds
            )
        ];

        if (relations.isEmpty()) {
            throw new AuraHandledException(
                'No relationship found. Please connect contacts before syncing.');
        }

        if (!skipPerformSync) {
            performSync(new Set<Id>{ recordId });
        }
    }


    private static Boolean isRunning = false;

    /* =========================================================
       ENTRY FROM CONTACT-CONTACT RELATIONSHIP
    ========================================================== */
    public static void syncFromCCR(
        List<HealthCloudGA__ContactContactRelation__c> ccrList) {

        if (isRunning || ccrList == null || ccrList.isEmpty()) {
            return;
        }

        isRunning = true;
        Set<Id> primaryAccountIds = new Set<Id>();

        try {

            Set<Id> contactIds = new Set<Id>();
            for (HealthCloudGA__ContactContactRelation__c ccr : ccrList) {
                if (ccr.Relationship_Status__c == 'Related') {
                    if (ccr.HealthCloudGA__Contact__c != null)
                        contactIds.add(ccr.HealthCloudGA__Contact__c);
                    if (ccr.HealthCloudGA__RelatedContact__c != null)
                        contactIds.add(ccr.HealthCloudGA__RelatedContact__c);
                }
            }

            if (contactIds.isEmpty()) {
                isRunning = false;
                return;
            }

            Map<Id, Contact> contactMap = new Map<Id, Contact>(
                [SELECT Id, AccountId, Account.Is_Primary__c,
                        Account.IsPersonAccount
                 FROM Contact
                 WHERE Id IN :contactIds]
            );

            for (Contact con : contactMap.values()) {
                if (con.Account.IsPersonAccount &&
                    con.Account.Is_Primary__c) {
                    primaryAccountIds.add(con.AccountId);
                }
            }

            if (!primaryAccountIds.isEmpty() && !skipPerformSync) {
                performSync(primaryAccountIds);
            }

        } catch (Exception e) {
            sendErrorEmail(primaryAccountIds, e);
        } finally {
            isRunning = false;
        }
    }


    /* =========================================================
       PRIMARY VALIDATION (BEFORE UPDATE SAFE)
    ========================================================== */
    public static void validatePrimary(
        Set<Id> primaryAccountIds,
        Map<Id, Account> newMap) {

        if (primaryAccountIds == null || primaryAccountIds.isEmpty()) {
            return;
        }

        Map<Id, Contact> primaryContacts = new Map<Id, Contact>(
            [SELECT Id, AccountId
             FROM Contact
             WHERE AccountId IN :primaryAccountIds]
        );

        Set<Id> primaryContactIds = new Set<Id>();
        for (Contact c : primaryContacts.values()) {
            primaryContactIds.add(c.Id);
        }

        if (primaryContactIds.isEmpty()) return;

        List<HealthCloudGA__ContactContactRelation__c> relations =
            [SELECT HealthCloudGA__Contact__c,
                    HealthCloudGA__RelatedContact__c
             FROM HealthCloudGA__ContactContactRelation__c
             WHERE Relationship_Status__c = 'Related'
             AND (
                  HealthCloudGA__Contact__c IN :primaryContactIds
                  OR
                  HealthCloudGA__RelatedContact__c IN :primaryContactIds
                 )];

        if (relations.isEmpty()) return;

        Set<Id> relatedContactIds = new Set<Id>();
        for (HealthCloudGA__ContactContactRelation__c rel : relations) {
            relatedContactIds.add(rel.HealthCloudGA__Contact__c);
            relatedContactIds.add(rel.HealthCloudGA__RelatedContact__c);
        }

        if (relatedContactIds.isEmpty()) return;

        Map<Id, Contact> relatedContacts = new Map<Id, Contact>(
            [SELECT Id, AccountId, Account.Is_Primary__c
             FROM Contact
             WHERE Id IN :relatedContactIds]
        );

        for (Id accId : primaryAccountIds) {
            for (Contact rc : relatedContacts.values()) {
                if (rc.AccountId != accId && rc.Account.Is_Primary__c) {
                    newMap.get(accId).addError(
                        'One account in this relationship group is already ' +
                        'marked as Primary. Only one Primary account is allowed.'
                    );
                }
            }
        }
    }


    /* =========================================================
       CORE SYNC ENGINE
    ========================================================== */
    private static void performSync(Set<Id> primaryIds) {

        // Allow test injection to bypass real custom metadata
        String rawFields = testFieldsToCopy;

        if (rawFields == null) {
            WellSpring_Configurations__mdt config =
                WellSpring_Configurations__mdt.getInstance('Patient_Data_Sync');
            if (config == null ||
                String.isBlank(config.Data_Transfer_Fields__c)) {
                return;
            }
            rawFields = config.Data_Transfer_Fields__c;
        }

        List<String> fieldsToCopy = rawFields.split(';');
        if (fieldsToCopy.isEmpty()) return;

        String fieldQuery = String.join(fieldsToCopy, ',');

        Map<Id, Account> primaryMap =
            new Map<Id, Account>(
                (List<Account>) Database.query(
                    'SELECT Id,' + fieldQuery +
                    ' FROM Account WHERE Id IN :primaryIds')
            );

        Set<Id> primaryContactIds  = new Set<Id>();
        Map<Id, Id> contactToAccountMap = new Map<Id, Id>();

        for (Contact c :
            [SELECT Id, AccountId
             FROM Contact
             WHERE AccountId IN :primaryIds]) {
            primaryContactIds.add(c.Id);
            contactToAccountMap.put(c.Id, c.AccountId);
        }

        if (primaryContactIds.isEmpty()) return;

        List<HealthCloudGA__ContactContactRelation__c> rels =
            [SELECT HealthCloudGA__Contact__c,
                    HealthCloudGA__RelatedContact__c
             FROM HealthCloudGA__ContactContactRelation__c
             WHERE Relationship_Status__c = 'Related'
             AND (
                  HealthCloudGA__Contact__c IN :primaryContactIds
                  OR
                  HealthCloudGA__RelatedContact__c IN :primaryContactIds
                 )];

        if (rels.isEmpty()) return;

        Map<Id, Set<Id>> primaryToRelatedMap = new Map<Id, Set<Id>>();

        for (HealthCloudGA__ContactContactRelation__c r : rels) {

            Id c1   = r.HealthCloudGA__Contact__c;
            Id c2   = r.HealthCloudGA__RelatedContact__c;
            Id acc1 = contactToAccountMap.containsKey(c1) ?
                      contactToAccountMap.get(c1) : null;
            Id acc2 = contactToAccountMap.containsKey(c2) ?
                      contactToAccountMap.get(c2) : null;

            if (acc1 != null && primaryIds.contains(acc1)) {
                if (!primaryToRelatedMap.containsKey(acc1))
                    primaryToRelatedMap.put(acc1, new Set<Id>());
                Id relatedAcc =
                    [SELECT AccountId FROM Contact WHERE Id = :c2 LIMIT 1]
                    .AccountId;
                if (relatedAcc != acc1)
                    primaryToRelatedMap.get(acc1).add(relatedAcc);
            }

            if (acc2 != null && primaryIds.contains(acc2)) {
                if (!primaryToRelatedMap.containsKey(acc2))
                    primaryToRelatedMap.put(acc2, new Set<Id>());
                Id relatedAcc =
                    [SELECT AccountId FROM Contact WHERE Id = :c1 LIMIT 1]
                    .AccountId;
                if (relatedAcc != acc2)
                    primaryToRelatedMap.get(acc2).add(relatedAcc);
            }
        }

        if (primaryToRelatedMap.isEmpty()) return;

        Set<Id> allRelatedIds = new Set<Id>();
        for (Set<Id> ids : primaryToRelatedMap.values()) {
            allRelatedIds.addAll(ids);
        }

        if (allRelatedIds.isEmpty()) return;

        List<Account> relatedAccounts =
            (List<Account>) Database.query(
                'SELECT Id,' + fieldQuery +
                ' FROM Account WHERE Id IN :allRelatedIds');

        Map<String, Schema.SObjectField> fieldMap =
            Account.SObjectType.getDescribe().fields.getMap();

        for (Account rel : relatedAccounts) {
            for (Id primaryId : primaryToRelatedMap.keySet()) {
                if (primaryToRelatedMap.get(primaryId).contains(rel.Id)) {
                    Account primary = primaryMap.get(primaryId);
                    for (String f : fieldsToCopy) {
                        f = f.trim();
                        if (fieldMap.containsKey(f) &&
                            fieldMap.get(f).getDescribe().isUpdateable()) {
                            rel.put(f, primary.get(f));
                        }
                    }
                }
            }
        }

        if (!relatedAccounts.isEmpty()) {
            update relatedAccounts;
        }
    }


    /* =========================================================
       ERROR EMAIL
    ========================================================== */
    public static void sendErrorEmail(Set<Id> primaryIds, Exception e) {

        if (skipEmailSend) return;

        List<OrgWideEmailAddress> owes = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true
            LIMIT 1
        ];

        Messaging.SingleEmailMessage mail =
            new Messaging.SingleEmailMessage();

        if (!owes.isEmpty()) {
            mail.setOrgWideEmailAddressId(owes[0].Id);
        }

        mail.setSubject('Relationship Data Sync Failed');
        mail.setToAddresses(new String[]{ UserInfo.getUserEmail() });
        mail.setPlainTextBody(
            'Primary Account Id(s): ' + primaryIds +
            '\nError Message: '        + e.getMessage() +
            '\nApex Exception: '       + e.getStackTraceString()
        );

        if (!Test.isRunningTest()) {
            Messaging.sendEmail(
                new Messaging.SingleEmailMessage[]{ mail }
            );
        }
    }
}