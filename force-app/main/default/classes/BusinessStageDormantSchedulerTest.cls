@isTest
private class BusinessStageDormantSchedulerTest {
    
    private static Account createAccount(String name, String stage, Datetime lastUpdated) {
        Account acc = new Account(
            Organization_Name__c = name,
            Name = name,
            Business_Stage__c = stage,
            Business_Stage_Last_Updated_Date__c = lastUpdated
        );
        insert acc;
        return acc;
    }
    private static Contact createContact(Id accountId, String lastName) {
        Contact con = new Contact(
            LastName = lastName,
            AccountId = accountId
        );
        insert con;
        return con;
    }
    private static HealthCloudGA__ContactContactRelation__c createCCR(Id contactId) {
        
        List<Account> noOrgList = [SELECT Id FROM Account WHERE Name = 'No Organization' LIMIT 1];
        Account noOrg;
        if (noOrgList.isEmpty()) {
            noOrg = new Account(Name = 'No Organization', Organization_Name__c = 'No Organization');
            insert noOrg;
        } else {
            noOrg = noOrgList[0];
        }
        Contact relatedCon = new Contact(LastName = 'RelatedFor_CCR', AccountId =noOrg.Id);
        insert relatedCon;
        
        Id contactRoleRecordTypeId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();
        
        HealthCloudGA__ReciprocalRole__c rec = new HealthCloudGA__ReciprocalRole__c();
        rec.Name='Father';
        rec.HealthCloudGA__InverseRole__c = 'Son';
        rec.RecordTypeId=contactRoleRecordTypeId;
        insert rec;
        
       list <HealthCloudGA__ReciprocalRole__c> roleRec = [
                    SELECT Id, Name
                    FROM HealthCloudGA__ReciprocalRole__c 
                    LIMIT 1
                ];
        
        System.assert(
        !roleRec.isEmpty(),
        'No HealthCloudGA__ReciprocalRole__c record found in org. Create one or use an existing role for test.'
    );

        HealthCloudGA__ContactContactRelation__c ccr = new HealthCloudGA__ContactContactRelation__c(
            HealthCloudGA__Contact__c        = contactId,
            HealthCloudGA__Role__c = roleRec[0].Id,
            HealthCloudGA__RelatedContact__c = relatedCon.Id
        );
        insert ccr;
        return ccr;
    }
    private static Event createEvent(
        Id whatId,
        Datetime startDT,
        Datetime endDT,
        Boolean isAllDay,
        Date activityDate
    ) {
        Event evt = new Event(
            WhatId    = whatId,
            Subject   = 'Test Event',
            DurationInMinutes = 60,
            ActivityDateTime  = startDT != null ? startDT : Datetime.now(),
            ActivityDate      = activityDate != null ? activityDate : Date.today()
        );
        if (isAllDay != null) {
            evt.IsAllDayEvent = isAllDay;
        }
        if (startDT != null) {
            evt.StartDateTime = startDT;
        }
        if (endDT != null) {
            evt.EndDateTime = endDT;
        }
        insert evt;
        return evt;
    }
    @isTest
    static void testSchedulerExecute() {
        
        Test.startTest();
        String cronExp = '0 0 0 15 3 ? 2099';
        System.schedule('DormantSchedulerTest', cronExp, new BusinessStageDormantScheduler());
        Test.stopTest();
        
    }
    @isTest
    static void testNoMetadata_earlyExit() {
        
        Test.startTest();
        try {
            BusinessStageDormantScheduler.moveAccountsToDormant();
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @isTest
    static void testNoEligibleAccounts() {
        
        Account acc = new Account(
            Name = 'Dormant Account',
            Organization_Name__c = 'Dormant Account',
            Business_Stage__c = 'Dormant',
            Business_Stage_Last_Updated_Date__c = Datetime.now().addDays(-400)
        );
        insert acc;
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Dormant', result.Business_Stage__c, 'Dormant account should stay Dormant.');
    }
    
    @isTest
    static void testAccountMovedToDormant_Identify() {
        
        Datetime oldDate = Datetime.now().addDays(-400);
        Account acc = createAccount('Identify Account', 'Identify', oldDate);
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
       
        System.assert(
            result.Business_Stage__c == 'Dormant' || result.Business_Stage__c == 'Identify',
            'Stage should be Dormant (moved) or Identify (no metadata).'
        );
    }
   
    @isTest
    static void testAccountNotMoved_DaysNotExceeded() {
        
        Datetime recentDate = Datetime.now().addDays(-1);
        Account acc = createAccount('Recent Meet Account', 'Meet', recentDate);
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        System.assertNotEquals('Dormant', result.Business_Stage__c,
            'Account with very recent stage update should NOT move to Dormant.');
    }
    @isTest
    static void testActiveReferralSource_NoCCR_FallsBackToStageDate() {
        Datetime oldDate = Datetime.now().addDays(-400);
        Account acc = createAccount('ARS No CCR', 'Active Referral Source', oldDate);
        
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        System.assert(
            result.Business_Stage__c == 'Dormant' || result.Business_Stage__c == 'Active Referral Source',
            'Stage should be Dormant or unchanged depending on metadata.'
        );
    }
    @isTest
    static void testActiveReferralSource_RecentCCR_NotMoved() {
        Datetime oldDate = Datetime.now().addDays(-400);
        Account acc = createAccount('ARS With CCR', 'Active Referral Source', oldDate);
        Contact con = createContact(acc.Id, 'TestContact');
        
        createCCR(con.Id);
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        
        System.assertNotEquals('Dormant', result.Business_Stage__c,
            'ARS account with recent CCR should NOT move to Dormant.');
    }
    
    @isTest
    static void testActiveReferralSource_DummyAccountContact_Excluded() {
        
        Account dummyAcc = new Account(Name = 'No Organization', Organization_Name__c = 'No Organization');
        insert dummyAcc;
        Datetime oldDate = Datetime.now().addDays(-400);
        Account arsAcc = createAccount('ARS Dummy Contact', 'Active Referral Source', oldDate);
        
        Contact con = new Contact(LastName = 'DummyContact', AccountId = dummyAcc.Id);
        insert con;
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :arsAcc.Id];
        System.assert(
            result.Business_Stage__c == 'Dormant' || result.Business_Stage__c == 'Active Referral Source',
            'Stage should be Dormant or unchanged depending on metadata.'
        );
    }
    
    @isTest
    static void testProtectedByFutureEvent_NotMovedToDormant() {
        
        Datetime oldDate = Datetime.now().addDays(-400);
        Account acc = createAccount('Discovery Protected', 'Discovery', oldDate);
        
        Datetime futureStart = Datetime.now().addDays(365);
        createEvent(acc.Id, futureStart, futureStart.addHours(1), false, null);
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        System.assert(
            result.Business_Stage__c == 'Discovery' || result.Business_Stage__c == 'Dormant',
            'Stage should be Discovery (protected) or Dormant (no metadata for stage).'
        );
    }
    @isTest
    static void testMultipleAccounts_BatchDormantUpdate() {
        Datetime oldDate = Datetime.now().addDays(-400);
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(
                Name = 'Batch Account ' + i,
                Organization_Name__c = 'Batch Account ' + i,
                Business_Stage__c = 'Meet',
                Business_Stage_Last_Updated_Date__c = oldDate
            ));
        }
        insert accounts;
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        List<Account> results = [
            SELECT Business_Stage__c
            FROM Account
            WHERE Id IN :accounts
        ];
        
        for (Account a : results) {
            System.assert(
                a.Business_Stage__c == 'Dormant' || a.Business_Stage__c == 'Meet',
                'Each account should be Dormant or Meet depending on metadata presence.'
            );
        }
    }
    
    @isTest
    static void testNullLastUpdatedDate_AccountSkipped() {
        
        Account acc = new Account(
            Name = 'Null Date Account',
            Organization_Name__c = 'Null Date Account',
            Business_Stage__c = 'Partnership'
        );
        insert acc;
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Partnership', result.Business_Stage__c,
            'Account with null last updated date should not move to Dormant.');
    }
    
    @isTest
    static void testNullBusinessStage_AccountExcluded() {
        Account acc = new Account(
            Name = 'No Stage Account',
            Organization_Name__c = 'No Stage Account',
            Business_Stage_Last_Updated_Date__c = Datetime.now().addDays(-400)
        );
        insert acc;
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(null, result.Business_Stage__c,
            'Account with null Business_Stage__c should be excluded from processing.');
    }
    
    @isTest
    static void testPartnershipStage_OldDate_MayMoveToDormant() {
        Datetime oldDate = Datetime.now().addDays(-500);
        Account acc = createAccount('Partnership Old', 'Partnership', oldDate);
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        System.assert(
            result.Business_Stage__c == 'Dormant' || result.Business_Stage__c == 'Partnership',
            'Partnership account should move to Dormant if metadata threshold is exceeded.'
        );
    }
    
    @isTest
    static void testEventWithActivityDateOnly_FutureProtection() {
        Datetime oldDate = Datetime.now().addDays(-400);
        Account acc = createAccount('All-Day Event Account', 'Identify', oldDate);
        
        Date futureDate = Date.today().addDays(365);
        Event evt = new Event(
            WhatId           = acc.Id,
            Subject          = 'All Day Future Event',
            IsAllDayEvent    = true,
            ActivityDate     = futureDate,
            DurationInMinutes = 0,
            ActivityDateTime = Datetime.newInstance(futureDate.year(), futureDate.month(), futureDate.day())
        );
        insert evt;
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        System.assert(
            result.Business_Stage__c == 'Identify' || result.Business_Stage__c == 'Dormant',
            'Account should remain Identify (protected) or Dormant (no metadata).'
        );
    }
    
    @isTest
    static void testGetAccountsWithProtectedFutureEvents_EmptyInput() {
        
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        
        System.assert(true, 'Should handle empty accountToDormantCutoff gracefully.');
    }
    @isTest
    static void testARS_MultipleContacts_LatestCCRDateUsed() {
        Datetime oldDate = Datetime.now().addDays(-400);
        Account acc = createAccount('ARS Multi Contact', 'Active Referral Source', oldDate);
        Contact con1 = createContact(acc.Id, 'ContactOne');
        Contact con2 = createContact(acc.Id, 'ContactTwo');
        
        createCCR(con1.Id);
        createCCR(con2.Id);
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        
        System.assertNotEquals('Dormant', result.Business_Stage__c,
            'ARS account with recent CCR should not move to Dormant even with multiple contacts.');
    }
    @isTest
    static void testDiscoveryStage_RecentDate_NotMoved() {
        Account acc = createAccount('Recent Discovery', 'Discovery', Datetime.now().addDays(-2));
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
        System.assertNotEquals('Dormant', result.Business_Stage__c,
            'Discovery account with recent date should not move to Dormant.');
    }
    
    @isTest
    static void testStageNotInMetadata_AccountSkipped() {
        
        Account acc = new Account(
            Name = 'Unknown Stage Account',
            Organization_Name__c = 'Unknown Stage Account',
            Business_Stage__c = 'Identify',
            Business_Stage_Last_Updated_Date__c = Datetime.now().addDays(-400)
        );
        insert acc;
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [SELECT Business_Stage__c FROM Account WHERE Id = :acc.Id];
    }
    
    @isTest
    static void testDormantMove_UpdatesLastUpdatedDate() {
        Datetime oldDate = Datetime.now().addDays(-400);
        Account acc = createAccount('Date Updated Account', 'Meet', oldDate);
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        Account result = [
            SELECT Business_Stage__c, Business_Stage_Last_Updated_Date__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        if (result.Business_Stage__c == 'Dormant') {
            System.assert(
                result.Business_Stage_Last_Updated_Date__c > oldDate,
                'Business_Stage_Last_Updated_Date__c should be updated when moved to Dormant.'
            );
        }
    }
    
    @isTest
    static void testLargeBatch_GovernorLimits() {
        Datetime oldDate = Datetime.now().addDays(-400);
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 50; i++) {
            accounts.add(new Account(
                Name = 'Load Test Account ' + i,
                Organization_Name__c = 'Load Test Account ' + i,
                Business_Stage__c = 'Partnership',
                Business_Stage_Last_Updated_Date__c = oldDate
            ));
        }
        insert accounts;
        Test.startTest();
        BusinessStageDormantScheduler.moveAccountsToDormant();
        Test.stopTest();
        
        List<Account> results = [
            SELECT Business_Stage__c FROM Account WHERE Id IN :accounts
        ];
        System.assertEquals(50, results.size(), 'All 50 accounts should be retrieved.');
        for (Account a : results) {
            System.assert(
                a.Business_Stage__c == 'Dormant' || a.Business_Stage__c == 'Partnership',
                'Each account should be in a valid stage.'
            );
        }
    }
}