@IsTest
private class OpportunityReferralMetricsBatchTest {

    private static String getAnyActiveStageName() {
        return [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsActive = true
            ORDER BY SortOrder
            LIMIT 1
        ].MasterLabel;
    }

    private static Set<String> getActiveStageNames() {
        Set<String> names = new Set<String>();
        for (OpportunityStage s : [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsActive = true
        ]) {
            names.add(s.MasterLabel);
        }
        return names;
    }

    private static Opportunity buildOpp(String name, String stageName, Id primaryContactId) {
        Opportunity o = new Opportunity(
            Name = name,
            StageName = stageName,
            CloseDate = Date.today().addDays(15)
        );
        if (primaryContactId != null) {
            o.Primary_Contact__c = primaryContactId;
        }
        return o;
    }

    @IsTest
    static void testBatchUpdatesMetricsAndSkipsOppWithoutPrimaryContact() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact c = new Contact(
            LastName = 'Primary Contact',
            AccountId = acc.Id,
            Prospects_Referred__c = 1,
            // Intentionally null to validate null -> 0 logic
            Lifetime_Revenue__c = null
        );
        insert c;

        String baseStage = getAnyActiveStageName();

        Opportunity oppWithContact = buildOpp('Opp With Contact', baseStage, c.Id);
        Opportunity oppWithoutContact = buildOpp('Opp Without Contact', baseStage, null);
        insert new List<Opportunity>{ oppWithContact, oppWithoutContact };

        Test.startTest();
        Database.executeBatch(new OpportunityReferralMetricsBatch(), 50);
        Test.stopTest();

        Opportunity updatedWith = [
            SELECT StageName, Prospects_Referred__c, Clients_Referred__c, Lifetime_Revenue__c
            FROM Opportunity
            WHERE Id = :oppWithContact.Id
        ];

        Opportunity updatedWithout = [
            SELECT StageName, Prospects_Referred__c, Clients_Referred__c, Lifetime_Revenue__c
            FROM Opportunity
            WHERE Id = :oppWithoutContact.Id
        ];

        System.assertEquals(1, updatedWith.Prospects_Referred__c, 'Prospects should be copied from primary contact.');
        System.assertEquals(0, updatedWith.Clients_Referred__c, 'Null clients should be saved as 0.');
        System.assertEquals(0, updatedWith.Lifetime_Revenue__c, 'Null revenue should be saved as 0.');
        System.assertEquals(baseStage, updatedWith.StageName, 'Stage should remain same for total referrals < 2.');

        System.assertEquals(baseStage, updatedWithout.StageName, 'Record without primary contact is not part of batch scope.');
        System.assertEquals(null, updatedWithout.Prospects_Referred__c, 'No primary contact means no metrics update.');
        System.assertEquals(null, updatedWithout.Clients_Referred__c, 'No primary contact means no metrics update.');
        System.assertEquals(null, updatedWithout.Lifetime_Revenue__c, 'No primary contact means no metrics update.');
    }

    @IsTest
    static void testBatchStageTransitionsWhenTargetStagesExist() {
        Set<String> activeStages = getActiveStageNames();
        Boolean hasStage23 = activeStages.contains('Referrals 2-3 within 30 days');
        Boolean hasStage48 = activeStages.contains('Referrals 4-8 within 90 days');

        // If these stage values are not configured in this org, skip this specific assertion block.
        if (!hasStage23 || !hasStage48) {
            System.assert(true, 'Target stage values are not active in this org; skipping stage-transition assertions.');
            return;
        }

        Account acc = new Account(Name = 'Stage Test Account');
        insert acc;

        Contact c23 = new Contact(
            LastName = 'Contact d',
            AccountId = acc.Id,
            Prospects_Referred__c = 1,
            Clients_Referred__c = 1,
            Lifetime_Revenue__c = 100
        );
        Contact c48 = new Contact(
            LastName = 'Contact b',
            AccountId = acc.Id,
            Prospects_Referred__c = 2,
            Clients_Referred__c = 3,
            Lifetime_Revenue__c = 250
        );
        insert new List<Contact>{ c23, c48 };

        String baseStage = getAnyActiveStageName();

        Opportunity opp23 = buildOpp('Opp Stage 2-3', baseStage, c23.Id);
        Opportunity opp48 = buildOpp('Opp Stage 4-8', baseStage, c48.Id);
        insert new List<Opportunity>{ opp23, opp48 };

        Test.startTest();
        Database.executeBatch(new OpportunityReferralMetricsBatch(), 50);
        Test.stopTest();

        Map<Id, Opportunity> updated = new Map<Id, Opportunity>([
            SELECT StageName, Prospects_Referred__c, Clients_Referred__c, Lifetime_Revenue__c
            FROM Opportunity
            WHERE Id IN :new Set<Id>{ opp23.Id, opp48.Id }
        ]);

        System.assertEquals('Referrals 2-3 within 30 days', updated.get(opp23.Id).StageName);
        System.assertEquals(1, updated.get(opp23.Id).Prospects_Referred__c);
        System.assertEquals(1, updated.get(opp23.Id).Clients_Referred__c);
        System.assertEquals(100, updated.get(opp23.Id).Lifetime_Revenue__c);

        System.assertEquals('Referrals 4-8 within 90 days', updated.get(opp48.Id).StageName);
        System.assertEquals(2, updated.get(opp48.Id).Prospects_Referred__c);
        System.assertEquals(3, updated.get(opp48.Id).Clients_Referred__c);
        System.assertEquals(250, updated.get(opp48.Id).Lifetime_Revenue__c);
    }
    @IsTest
static void testAccountLevelRollup_WhenNoPrimaryContact() {

    Account acc = new Account(Name = 'Rollup Account');
    insert acc;

    // Multiple contacts under same account
    Contact c1 = new Contact(
        LastName = 'Ca',
        AccountId = acc.Id,
        Prospects_Referred__c = 1,
        Clients_Referred__c = 2,
        Lifetime_Revenue__c = 100
    );

    Contact c2 = new Contact(
        LastName = 'Cb',
        AccountId = acc.Id,
        Prospects_Referred__c = 2,
        Clients_Referred__c = 1,
        Lifetime_Revenue__c = 200
    );

    insert new List<Contact>{ c1, c2 };

    String baseStage = getAnyActiveStageName();

    // ❗ No Primary Contact → triggers ACCOUNT ROLLUP logic
    Opportunity opp = new Opportunity(
        Name = 'Rollup Opp',
        StageName = baseStage,
        CloseDate = Date.today().addDays(10),
        AccountId = acc.Id   // 🔥 CRITICAL
    );
    insert opp;

    Test.startTest();
    Database.executeBatch(new OpportunityReferralMetricsBatch(), 50);
    Test.stopTest();

    Opportunity updated = [
        SELECT Prospects_Referred__c, Clients_Referred__c, Lifetime_Revenue__c, StageName
        FROM Opportunity
        WHERE Id = :opp.Id
    ];

    // Expected totals
    System.assertEquals(3, updated.Prospects_Referred__c); // 1 + 2
    System.assertEquals(3, updated.Clients_Referred__c);   // 2 + 1
    System.assertEquals(300, updated.Lifetime_Revenue__c); // 100 + 200

    // totalReferrals = 6 → should go to 4-8 stage IF exists
}
}