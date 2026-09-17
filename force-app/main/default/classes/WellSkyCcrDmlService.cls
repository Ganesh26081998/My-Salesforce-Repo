/**
 * Inserts Health Cloud CCRs without sharing so deploy tests can run as Veera
 * while test data is created under the default test execution user.
 */
public without sharing class WellSkyCcrDmlService {

    public static void insertCcr(HealthCloudGA__ContactContactRelation__c ccr) {
        insert ccr;
    }
}