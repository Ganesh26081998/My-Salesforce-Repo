/*
----------------------------------------------------------------------------
Author        : Bhanu Prakash
Class Name    : prospectWarningController
CreatedOn     : 21-01-2026
LastModifiedOn: 10-05-2026
LastModifiedBy: Bhanu Prakash
Description   : This controller is used to retrieve prospect-related information, including referral source and existing business or individual contact relationships associated with a patient account.



----------------------------------------------------------------------------
*/

public with sharing class prospectWarningController {
    public class ProspectInfo {
        @AuraEnabled public Boolean Businessflag;
        @AuraEnabled public Boolean Individualflag;
        @AuraEnabled public String self;

        public ProspectInfo(Boolean Businessflag, Boolean Individualflag, String self) {
            this.Businessflag = Businessflag;
            this.Individualflag = Individualflag;
            this.self = self;

        }
    }
    @AuraEnabled
    public static ProspectInfo getProspectInfo(Id accountId) {
        if (accountId == null) {
            return null;
        }
        Account acc = [SELECT HowDidYouFindUs__c, IsPersonAccount,PersonContactId
                        FROM Account
                        WHERE Id = :accountId 
                        LIMIT 1
                        ];

        Boolean Businessflag = false;
        Boolean Individualflag = false;
        String Busniess =  System.Label.Contact_Business_RecordType ;
        String Individual =  System.Label.Contact_Individual_RecordType ;
        Businessflag = [
            SELECT COUNT()
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE HealthCloudGA__RelatedContact__c = :acc.PersonContactId AND HealthCloudGA__Contact__r.RecordType.DeveloperName = :Busniess
              AND IsDeleted = false
        ] > 0;
        Individualflag = [
            SELECT COUNT()
            FROM HealthCloudGA__ContactContactRelation__c
            WHERE HealthCloudGA__RelatedContact__c = :acc.PersonContactId AND HealthCloudGA__Contact__r.RecordType.DeveloperName = :Individual
              AND IsDeleted = false
        ] > 0;

        return new ProspectInfo(
            Businessflag,
            Individualflag,
            acc.HowDidYouFindUs__c
        );
    }
}