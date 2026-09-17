public with sharing class BusinessStageDormantScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        moveAccountsToDormant();
    }

    public static void moveAccountsToDormant() {
        Map<String, Integer> stageToDaysMap = new Map<String, Integer>();
        Set<String> stagesRequiringFutureEventCheck = new Set<String>();

        String dormantStage;
        String activeReferralSourceStage;
        String dummyAccountName;

        for (WellSpring_Configurations__mdt rec : [
            SELECT Business_Stage_Value__c,
                   Dormant_After_Days__c,
                   Is_Dormant_Stage__c,
                   Is_Active_Referral_Source__c,
                   Requires_Future_Event_Check__c,
                   Dummy_Account_Name__c
            FROM WellSpring_Configurations__mdt
        ]) {
            if (rec.Business_Stage_Value__c != null && rec.Dormant_After_Days__c != null) {
                stageToDaysMap.put(
                    rec.Business_Stage_Value__c,
                    Integer.valueOf(rec.Dormant_After_Days__c)
                );
            }

            if (rec.Requires_Future_Event_Check__c && rec.Business_Stage_Value__c != null) {
                stagesRequiringFutureEventCheck.add(rec.Business_Stage_Value__c);
            }

            if (rec.Is_Dormant_Stage__c && rec.Business_Stage_Value__c != null) {
                dormantStage = rec.Business_Stage_Value__c;
            }

            if (rec.Is_Active_Referral_Source__c && rec.Business_Stage_Value__c != null) {
                activeReferralSourceStage = rec.Business_Stage_Value__c;
            }

            if (rec.Dummy_Account_Name__c != null) {
                dummyAccountName = rec.Dummy_Account_Name__c;
            }
        }

        if (stageToDaysMap.isEmpty()) {
            System.debug('Stage timeline metadata not found.');
            return;
        }

        List<Account> accounts = [
            SELECT Id,
                   Name,
                   Business_Stage__c,
                   Business_Stage_Last_Updated_Date__c,
                   Dormant_Notification_Sent__c
            FROM Account
            WHERE Business_Stage__c != null
            AND Business_Stage__c != :dormantStage
            AND Business_Stage_Last_Updated_Date__c != null
        ];

        if (accounts.isEmpty()) {
            System.debug('No eligible Accounts found.');
            return;
        }

        Set<Id> activeReferralSourceAccountIds = new Set<Id>();
        Map<Id, Datetime> accountToDormantCutoff = new Map<Id, Datetime>();

        for (Account acc : accounts) {
            if (acc.Business_Stage__c == activeReferralSourceStage) {
                activeReferralSourceAccountIds.add(acc.Id);
            }

            if (stagesRequiringFutureEventCheck.contains(acc.Business_Stage__c)) {
                Integer allowedDays = stageToDaysMap.get(acc.Business_Stage__c);

                if (allowedDays != null && acc.Business_Stage_Last_Updated_Date__c != null) {
                    accountToDormantCutoff.put(
                        acc.Id,
                        acc.Business_Stage_Last_Updated_Date__c.addDays(allowedDays)
                    );
                }
            }
        }

        Map<Id, Datetime> accountToLastReferralDate =
            getLastReferralDateByAccount(activeReferralSourceAccountIds, dummyAccountName);

        Set<Id> accountsWithProtectedFutureEvents =
            getAccountsWithProtectedFutureEvents(accountToDormantCutoff);

        Date todayDate = Date.today();
        Datetime nowDateTime = System.now();

        List<Account> accountsToMoveDormant = new List<Account>();

        for (Account acc : accounts) {
            Integer allowedDays = stageToDaysMap.get(acc.Business_Stage__c);
            if (allowedDays == null) {
                System.debug(
                    'No metadata timeline found for stage: ' +
                    acc.Business_Stage__c +
                    ' | Account: ' + acc.Id
                );
                continue;
            }

            Datetime referenceDateTime;

            if (acc.Business_Stage__c == activeReferralSourceStage) {
                referenceDateTime = accountToLastReferralDate.get(acc.Id);

                if (referenceDateTime == null) {
                    referenceDateTime = acc.Business_Stage_Last_Updated_Date__c;
                }
            } else {
                referenceDateTime = acc.Business_Stage_Last_Updated_Date__c;
            }

            if (referenceDateTime == null) {
                System.debug('Reference date is null for Account: ' + acc.Id);
                continue;
            }

            Integer daysElapsed = referenceDateTime.date().daysBetween(todayDate);

            System.debug(
                'Account: ' + acc.Id +
                ' | Stage: ' + acc.Business_Stage__c +
                ' | Allowed Days: ' + allowedDays +
                ' | Reference Date: ' + referenceDateTime +
                ' | Days Elapsed: ' + daysElapsed
            );

            if (daysElapsed < allowedDays) {
                continue;
            }

            if (accountsWithProtectedFutureEvents.contains(acc.Id)) {
                System.debug(
                    'Skipping Dormant update because qualifying future Event exists for Account: ' +
                    acc.Id
                );
                continue;
            }

            accountsToMoveDormant.add(new Account(
                Id = acc.Id,
                Business_Stage__c = dormantStage,
                Business_Stage_Last_Updated_Date__c = nowDateTime
            ));
        }

        if (!accountsToMoveDormant.isEmpty()) {
            update accountsToMoveDormant;
        }

        System.debug('FINAL SUMMARY -> Accounts moved to Dormant: ' + accountsToMoveDormant.size());
    }

    private static Map<Id, Datetime> getLastReferralDateByAccount(Set<Id> accountIds, String dummyAccountName) {
        Map<Id, Datetime> accountToLastReferralDate = new Map<Id, Datetime>();

        if (accountIds == null || accountIds.isEmpty()) {
            return accountToLastReferralDate;
        }

        Map<Id, Id> contactToAccountId = new Map<Id, Id>();

        for (Contact con : [
            SELECT Id, AccountId, Account.Name
            FROM Contact
            WHERE AccountId IN :accountIds
            AND Account.Name != :dummyAccountName
        ]) {
            contactToAccountId.put(con.Id, con.AccountId);
        }

        if (contactToAccountId.isEmpty()) {
            return accountToLastReferralDate;
        }

        for (AggregateResult ar : [
            SELECT HealthCloudGA__Contact__c contactId,
                   MAX(CreatedDate) lastReferralDate
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE HealthCloudGA__Contact__c IN :contactToAccountId.keySet()
            GROUP BY HealthCloudGA__Contact__c
        ]) {
            Id contactId = (Id) ar.get('contactId');
            Datetime lastReferralDate = (Datetime) ar.get('lastReferralDate');
            Id accountId = contactToAccountId.get(contactId);

            if (accountId == null || lastReferralDate == null) {
                continue;
            }

            Datetime existingDate = accountToLastReferralDate.get(accountId);

            if (existingDate == null || lastReferralDate.getTime() > existingDate.getTime()) {
                accountToLastReferralDate.put(accountId, lastReferralDate);
            }
        }

        return accountToLastReferralDate;
    }

    private static Set<Id> getAccountsWithProtectedFutureEvents(Map<Id, Datetime> accountToDormantCutoff) {
        Set<Id> protectedAccountIds = new Set<Id>();

        if (accountToDormantCutoff == null || accountToDormantCutoff.isEmpty()) {
            return protectedAccountIds;
        }

        List<Event> relatedEvents = [
            SELECT Id,
                   WhatId,
                   CreatedDate,
                   ActivityDate,
                   StartDateTime,
                   EndDateTime,
                   IsAllDayEvent
            FROM Event
            WHERE WhatId IN :accountToDormantCutoff.keySet()
            AND IsDeleted = false
            AND IsArchived = false
        ];

        for (Event evt : relatedEvents) {
            Id accountId = evt.WhatId;
            Datetime dormantCutoff = accountToDormantCutoff.get(accountId);

            if (accountId == null || dormantCutoff == null || evt.CreatedDate == null) {
                continue;
            }

            Datetime scheduledDateTime = getEventScheduledDateTime(evt);
            if (scheduledDateTime == null) {
                continue;
            }

            if (evt.CreatedDate.getTime() <= dormantCutoff.getTime()
                && scheduledDateTime.getTime() >= dormantCutoff.getTime()) {
                protectedAccountIds.add(accountId);
            }
        }

        return protectedAccountIds;
    }

    private static Datetime getEventScheduledDateTime(Event evt) {
        if (evt == null) {
            return null;
        }

        if (evt.StartDateTime != null) {
            return evt.StartDateTime;
        }

        if (evt.EndDateTime != null) {
            return evt.EndDateTime;
        }

        if (evt.ActivityDate != null) {
            return Datetime.newInstance(
                evt.ActivityDate.year(),
                evt.ActivityDate.month(),
                evt.ActivityDate.day()
            );
        }

        return null;
    }
}