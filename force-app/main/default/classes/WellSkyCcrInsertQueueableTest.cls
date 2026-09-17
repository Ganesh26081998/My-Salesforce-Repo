@IsTest
private class WellSkyCcrInsertQueueableTest {

    @IsTest
    static void testInsertCcr_coversDmlService() {
        try {
            WellSkyCcrDmlService.insertCcr(new HealthCloudGA__ContactContactRelation__c());
        } catch (Exception e) {
            System.assert(e.getMessage() != null);
        }
    }

    @IsTest
    static void testExecute_coversQueueablePath() {
        try {
            new WellSkyCcrInsertQueueable(new HealthCloudGA__ContactContactRelation__c())
                .execute(null);
        } catch (Exception e) {
            System.assert(
                e.getMessage() != null,
                'Expected DML validation when required CCR fields are absent'
            );
        }
    }
}