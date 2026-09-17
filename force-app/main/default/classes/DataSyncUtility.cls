public with sharing class DataSyncUtility {
    public static void createApplicationLog(String level, String message, String function, String source) {
        // TODO: let's rename Application_Log__c to DataSync_Log__c   Also probably create that DataSyncUtility class to hold this method.
        Data_Sync_Log__c log = new Data_Sync_Log__c();
        log.Level__c = level;
        log.Source__c = source;
        log.Function__c = function;
        log.Message__c = message.left(131072);
        insert log;
    }
    @future
    public static void asyncCreateApplicationLog(String level, String message, String function, String source) {
        DataSyncUtility.createApplicationLog(level, message, function, source);
    }
    
    /**************************************************************************************
     * @Description  This method extract value of inner attributes in a JSON
     * @Param		String - JSON string
     * @Param		String - JSON attribute path
     * @Return       String - This sample assumes returned value is a string
     * @Example
     * System.debug('Result:: '+DataSyncUtility.extractAttributeFromJson('{"data":{"user":{"organization":{"id":"123"}}}}', 'data.user.organization.id'));
     * System.debug('Result:: '+DataSyncUtility.extractAttributeFromJson('{"data":{"user":[{"organization":{"id":"123"}},{"organization":{"id":"421"}}]}}', 'data.user[0].organization.id'));
     * System.debug('Result:: '+DataSyncUtility.extractAttributeFromJson('{"data":{"user":[{"organization":[{"id":"111"},{"id":"999"}]},{"organization":{"id":"421"}}]}}', 'data.user[0].organization[1].id'));
     **************************************************************************************/
    // public static String extractAttributeFromJson(String jsonResponse, String attrString) {
        //     if(String.isBlank(jsonResponse) || String.isBlank(attrString)) return null;
        //     List<String> attrPath = attrString.split('\\.');
        //     Integer index = 0;
        //     Boolean runOne = false;
        //     Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
        //     Map<String, Object> m1;
        //     String updatedJSON;
        //     for(index = 0;index<=attrPath.size()-1;index++){
            //         String arryPosition;
            //         if(attrPath[index].contains('[')){
                //             List<String> innerArray = attrPath[index].split('\\[');
                //             //System.debug('innerArray:: '+innerArray);
                //             arryPosition = innerArray[1].split('')[0];
                //             //System.debug('arryPosition:: '+arryPosition);
                //             attrPath[index] = attrPath[index].split('\\[')[0];
            //         }
            
            //         if(!runOne)
            //         m1 = m;
            //         //System.debug('Before reInt:: '+m1);
            //         //System.debug('attrPath:: '+attrPath[index]);
            //         //System.debug('obj:: '+m1.get(attrPath[index]));
            //         //Object obj = m1.get(attrPath[index]);
            
            //         if(m1.get(attrPath[index]) instanceof List<Object>){
                //          List<Object> listData = (List<Object>)m1.get(attrPath[index]);
                //             //System.debug('List Value:: '+listData);
                //             String reJson = JSON.serialize(listData[Integer.valueOf(arryPosition)]);
                
                //             Map<String, Object> m2 = (Map<String, Object>) JSON.deserializeUntyped(reJson);
                //             //System.debug('m1:: '+m2);
                //             m1=m2;
                //             Continue;
            //         }
            //         if(attrPath.size()-1 == index){
                //          //System.debug('Final Result :: '+m1.get(attrPath[index]));
                //          return String.valueOf(m1.get(attrPath[index]));
            //         }
            //         m1 = (Map<String, Object>)m1.get(attrPath[index]);
            //         //System.debug('After reInt:: '+m1);
            //         runOne = true;
        //     }
        //     return null;
    // }
}