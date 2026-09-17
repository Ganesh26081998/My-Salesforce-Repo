global class BusinessAccountMetricsBatch implements Database.Batchable<SObject> {

    private static final Integer THIRTY_DAYS = 30;
    private static final Integer NINETY_DAYS = 90;
    private static final Decimal REFERRALS_2_3_MIN = 2;
    private static final Decimal REFERRALS_2_3_MAX = 3;
    private static final Decimal REFERRALS_4_8_MIN = 4;
    private static final Decimal REFERRALS_4_8_MAX = 8;
    private static final String STAGE_REFERRALS_2_3 = 'Referrals 2-3 within 30 days';
    private static final String STAGE_REFERRALS_4_8 = 'Referrals 4-8 within 90 days';

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, CreatedDate, Business_Stage__c 
            FROM Account 
            WHERE IsPersonAccount = false
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Account> scope) {
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : scope) {
            accountIds.add(acc.Id);
        }

        Map<Id, AggregateResult> accountToMetricsMap = new Map<Id, AggregateResult>();
        List<AggregateResult> aggregations = [
            SELECT AccountId,
                   SUM(Lifetime_Revenue__c) totalRevenue,
                   SUM(Clients_Referred__c) totalClients,
                   SUM(Prospects_Referred__c) totalProspects
            FROM Contact
            WHERE AccountId IN :accountIds
            GROUP BY AccountId
        ];

        for (AggregateResult ar : aggregations) {
            accountToMetricsMap.put((Id) ar.get('AccountId'), ar);
        }

        List<Account> accountsToUpdate = new List<Account>();

        for (Account originalAcc : scope) {
            Decimal revenue = 0;
            Decimal clients = 0;
            Decimal prospects = 0;

            if (accountToMetricsMap.containsKey(originalAcc.Id)) {
                AggregateResult ar = accountToMetricsMap.get(originalAcc.Id);
                revenue = ar.get('totalRevenue') != null ? (Decimal) ar.get('totalRevenue') : 0;
                clients = ar.get('totalClients') != null ? (Decimal) ar.get('totalClients') : 0;
                prospects = ar.get('totalProspects') != null ? (Decimal) ar.get('totalProspects') : 0;
            }

            Decimal totalReferrals = clients + prospects;
            String targetStage = getBusinessStage(originalAcc.CreatedDate, totalReferrals);

            Account updatedAcc = new Account(
                Id = originalAcc.Id,
                Clients_Referred__c = clients,
                Prospects_Referred__c = prospects,
                Lifetime_Revenue__c = revenue
            );

            if (!String.isBlank(targetStage)) {
                updatedAcc.Business_Stage__c = targetStage;
            }

            accountsToUpdate.add(updatedAcc);
        }

        if (!accountsToUpdate.isEmpty()) {
            Database.update(accountsToUpdate, false);
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('=== [FINISH] BusinessAccountMetricsBatch Completed ===');
    }

    private static String getBusinessStage(Datetime accountCreatedDate, Decimal totalReferrals) {
        if (accountCreatedDate == null) return null;
        Integer accountAgeInDays = accountCreatedDate.date().daysBetween(Date.today());
        Decimal safeTotalReferrals = totalReferrals == null ? 0 : totalReferrals;

        if (accountAgeInDays <= NINETY_DAYS && safeTotalReferrals >= REFERRALS_4_8_MIN && safeTotalReferrals <= REFERRALS_4_8_MAX) {
            return STAGE_REFERRALS_4_8;
        }
        if (accountAgeInDays <= THIRTY_DAYS && safeTotalReferrals >= REFERRALS_2_3_MIN && safeTotalReferrals <= REFERRALS_2_3_MAX) {
            return STAGE_REFERRALS_2_3;
        }
        return null;
    }
}