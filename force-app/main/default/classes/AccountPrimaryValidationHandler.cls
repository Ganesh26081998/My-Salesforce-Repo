public with sharing class AccountPrimaryValidationHandler {

    // Entry point from Trigger
    public static void handle(List<Account> newList, Map<Id, Account> oldMap) {
        handle(newList, oldMap, false);
    }

    // Testable method with bypass flag
    public static void handle(List<Account> newList,
                              Map<Id, Account> oldMap,
                              Boolean bypassCustomSetting) {

        if(newList == null || newList.isEmpty()){
            return;
        }

        // Step 1: Custom Setting Check
        if(!bypassCustomSetting){
            WellSky_Custom_Setting__c cs = WellSky_Custom_Setting__c.getInstance();

            if(cs == null || !cs.Run_Triggers__c){
                return;
            }
        }

        // Step 2: Find becoming Primary
        Set<Id> becomingPrimary = new Set<Id>();

        for(Account acc : newList){

            Account oldRec = oldMap != null ? oldMap.get(acc.Id) : null;

            if(acc.Is_Primary__c &&
               (oldRec == null || !oldRec.Is_Primary__c)){

                becomingPrimary.add(acc.Id);
            }
        }

        // Step 3: Call business logic
        if(!becomingPrimary.isEmpty()){
            WellSkyRelationshipHandler.validatePrimary(
                becomingPrimary,
                new Map<Id, Account>(newList)
            );
        }
    }
}