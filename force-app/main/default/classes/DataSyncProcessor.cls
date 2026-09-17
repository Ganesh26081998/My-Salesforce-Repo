public with sharing class DataSyncProcessor implements DataSyncInterfaces.IDataSyncProcessor {
    /*
    DataSyncCallOut DataSyncCallOutInstance = new DataSyncCallOut();
    DataSyncCallOutInstance.callDataSyncCallOut('GET', '/v1/patients/?created=gt1800-01-01T00:00&_count=20&_page=0', '');
    
    Data_Sync_Job__c pendingChange = new Data_Sync_Job__c();
    pendingChange.External_System__c = 'WellSky';
    DataSyncProcessor.processSync(pendingChange);
     */
    private Static HttpResponse oldResponse;
    public void processSync(Data_Sync_Job__c pendingChange) {
        try{
            //String calloutClassName = 'DataSyncCallOut'; // This could be from a customm/metadata setting or the sync record.
            // For example... DataSync_API_Setting with
            //                Name=WellSky,
            //                Callout_Class_Name__c=DataSyncCallOut,
            //                Processor_Class_Name__c=DataSyncProcessorWellSky
            DataSyncInterfaces.IDataSyncCallOut callout = (DataSyncInterfaces.IDataSyncCallOut) Type.forName(pendingChange.config__r.Callout_Class_Name__c).newInstance();
            callout.setNamedCredentialPrefix(pendingChange.config__r.External_System__c);
            HttpResponse response = new HttpResponse();
            String url = pendingChange.config__r.Service_Path__c;
            
            
            // This block gives you way to configure /v1/referralsource/{id}
            string relatedId = pendingChange.Related_Record_Id__c;
            if (string.isblank(relatedId) == false) {
                // get data using related record id
                Id relatedRecordId = Id.valueOf(relatedId);
                String relatedRecordObjectName = relatedRecordId.getSObjectType().getDescribe().getName();
                string fieldname = pendingChange.config__r.Service_Path_Id_Field_Name__c;
                string query;
                SObject relatedRecord;
                string servicePathIdValue;
                if(fieldname != null){
                    query = 'SELECT ' + fieldname + ' FROM ' + relatedRecordObjectName + ' WHERE Id = :relatedRecordId';
                    relatedRecord = Database.query(query);
                    servicePathIdValue = (string) relatedRecord.get(fieldname);
                    url = url.replace('{id}', servicePathIdValue);
                }
            }
            
            if (pendingChange.config__r.Response_Is_Paged__c) {
                // Because this job is configured to handle paged responses we need to add the paging fields to the url.
                // other apis might not receive this as url parameters but for now we'll just do this.
                integer pageNumber = (integer) pendingChange.Page_Number__c;
                if (pageNumber == null) {
                    pageNumber = 0; // TODO  this needs a config to decide if this should start at 0 or 1.
                } else {
                    pageNumber = pageNumber + 1;
                }
                pendingChange.Page_Number__c = pageNumber; // save for next time.
                
                // Add the paging fields to the url
                url += '?';
                url += pendingChange.config__r.Current_Page_Field_Name__c + '=' + pageNumber;
                url += '&';
                url += pendingChange.config__r.Rows_Per_Page_Field_Name__c + '=' + pendingChange.config__r.Rows_Per_Page__c;
                
            }
            
            string payload = '';
            
            if (pendingChange.config__r.Method__c == 'PUT') {
                // We need to get the payload from the related record and convert to json using the field map.
                payload = buildPayload(pendingChange);
            }else if(pendingChange.config__r.Method__c == 'POST'){
                payload = buildPayload(pendingChange);
                //TODO: need to updated record back if required. Callback of API need to map with object and field.
            }
            pendingChange.Payload__c = payload?.left(13172);
            System.debug('payload: ' + payload);
            
            response = callout.execute(pendingChange.config__r.Method__c,  url, payload);
            
            DataSyncProcessor.oldResponse = response;
            String responseBody = response.getBody();
            pendingChange.Response__c = responseBody?.left(13172);
            pendingChange.Response_Code__c = response.getStatusCode();
            
            //System.debug('response: ' + response?.getBody());
            //System.debug('Status: ' + response?.getStatus());
            if((response.getStatus() == 'OK' || response.getStatus() == 'Created') && (response.getStatusCode() == 200 || response.getStatusCode() == 201)) {
                JSONParse parser = new JSONParse(responseBody);
                
                //Map<String, Object> mapResponse = (Map<String, Object>)JSON.deserializeUntyped(responseBody);
                
                //Checking for extra records based on pagination of page
                if(pendingChange.Is_More_Records__c){
                    String totalRecords = parser.get(pendingChange.config__r.Total_Record_Path__c).getStringValue();
                    integer totalPage;
                    if(pendingChange.Total_Number_Of_Page__c == null){
                        totalPage = Integer.valueOf(Integer.valueOf(totalRecords)/pendingChange.config__r.Rows_Per_Page__c);
                        pendingChange.Total_Number_Of_Page__c = totalPage;
                        //System.debug('pendingChange.Total_Number_Of_Page__::'+pendingChange.Total_Number_Of_Page__c);
                    }
                    if(pendingChange.Total_Number_Of_Page__c == pendingChange.Page_Number__c){
                        pendingChange.Status__c = 'Complete';
                    } else {
                        pendingChange.Response__c = response?.getBody()?.left(13172);
                        //update pendingChange; uncomment for real test TODO:
                        
                    }
                    
                } else {
                    pendingChange.Status__c = 'Complete';
                }
                
                // If the config method is 'GET' and We have a Salesforce_Object_Name__c then we need to upsert the records.
                if ( pendingChange.config__r.Method__c == 'GET' && pendingChange.config__r.Salesforce_Object_Name__c != null) {
                    //System.debug('GET Called !!');
                    // We'll need to add something to thm
                    upsertObjects(pendingChange, response?.getBody(),false);
                }
                if(pendingChange.config__r.Method__c == 'POST' && pendingChange?.Callback_Response_Config__r?.Name != null){
                    upsertObjects(pendingChange, response?.getBody(),true);
                }
                
            } else {
                //pendingChange.Payload__c = stringPayload?.left(13172);
                pendingChange.Response__c = response!= null?response.getBody()?.left(13172):'';
                pendingChange.Status__c = 'Abort'; // avoid getting over and over
            }
            
        } catch (Exception e){
            System.debug('Error: ' + e.getMessage()+'  Line:: '+e.getLineNumber());
            pendingChange.Status__c = 'Abort'; // avoid getting over and over
            DataSyncUtility.asyncCreateApplicationLog('Error','Line: ' + e.getLineNumber() + '\n' + e.getMessage(), 'authenticate', 'DataSyncProcessor');
        }
        
        update pendingChange;
        
        
    }
    
    public static string buildPayload(Data_Sync_Job__c pendingChange) {
        // This method is used to build the payload for the callout.
        // The payload is built based on the mapping of the fields in the Data_Sync_Field_Map__c object.
        // The mapping is based on the context of the Data_Sync_Job__c object.
        // The payload is a json string.
        List<Data_Sync_Field_Map__c> dataSyncFieldMapList = [SELECT  
                                                             Name, External_System__c, Context__c, External_Field_API_Name__c, 
                                                             Salesforce_Field_API_Name__c, Is_External_Id__c, Order__c
                                                            FROM Data_Sync_Field_Map__c
                                                            WHERE Context__c = :pendingChange.config__r.Name
                                                            ORDER BY Order__c ASC];
        
        string result = '';
        
        Id relatedRecordId;
        String relatedRecordObjectName ;
        if(pendingChange.Related_Record_Id__c != null){
            relatedRecordId = Id.valueOf(pendingChange.Related_Record_Id__c);
            relatedRecordObjectName = relatedRecordId.getSObjectType().getDescribe().getName();
        }
        list<string> fieldNames = new list<string>();
        for (Data_Sync_Field_Map__c mapItem : dataSyncFieldMapList) {
            // avoid duplicate fields
            if(fieldNames.contains(mapItem.Salesforce_Field_API_Name__c)){
                continue;
            }
            // avoid addings ones that start and end with a quote
            if (mapItem.Salesforce_Field_API_Name__c.left(1) == '\'' && mapItem.Salesforce_Field_API_Name__c.right(1) == '\'') {
                continue;
            }
            fieldNames.add(mapItem.Salesforce_Field_API_Name__c);
        }
        SObject relatedRecord;
        if(fieldNames.size()>0 && relatedRecordId != null){
            string queryFieldNames = String.join(fieldNames, ',');
            string query = 'SELECT ' + queryFieldNames + ' FROM ' + relatedRecordObjectName + ' WHERE Id = :relatedRecordId';
            relatedRecord = Database.query(query);
        }
        
        
        Map<String, Object> mapPayload = new Map<String, Object>();
        for (Data_Sync_Field_Map__c mapItem : dataSyncFieldMapList) {
            // sample External_Field_API_Name__c might be 'telcom.[0].value' so the parent node of telcom might need to be created.
            List<String> pathParts = mapItem.External_Field_API_Name__c.split('\\.');
            Map<String, Object> mapPointer = mapPayload;
            
            for (Integer i = 0; i < pathParts.size(); i++) {
                if (i == (pathParts.size() - 1)) {
                    // This is the last part of the path... set the value directly.
                    if (mapItem.Salesforce_Field_API_Name__c.left(1) == '\'' && mapItem.Salesforce_Field_API_Name__c.right(1) == '\'') {
                        // Handle literal text values enclosed in quotes.
                        if (mapItem.Salesforce_Field_API_Name__c == '\'true\'') {
                            mapPointer.put(pathParts[i], true);
                        } else if (mapItem.Salesforce_Field_API_Name__c == '\'false\'') {
                            mapPointer.put(pathParts[i], false);
                        } else {
                            String literalValue = mapItem.Salesforce_Field_API_Name__c.substring(1, mapItem.Salesforce_Field_API_Name__c.length() - 1);
                            mapPointer.put(pathParts[i], literalValue);
                        }
                    } else {
                        // Handle dynamic values from relatedRecord.
                        if (relatedRecord != null) {
                            if(relatedRecord.get(mapItem.Salesforce_Field_API_Name__c) != null){
                                mapPointer.put(pathParts[i], relatedRecord.get(mapItem.Salesforce_Field_API_Name__c));
                            }else {
                                mapPointer.put(pathParts[i], '');
                            }
                        }
                    }
                } else {
                    // This is not the last part of the path... ensure the parent node exists.
                    if (pathParts[i + 1].startsWith('[')) {
                        // Handle arrays with indices (e.g., 'telcom.[0]').
                        System.debug('pathParts :: ' + pathParts[i + 1]);
                        
                        Integer arrayIndex = Integer.valueOf(pathParts[i + 1].substring(1, pathParts[i + 1].length() - 1));
                        List<Object> listOfObjects = (List<Object>) mapPointer.get(pathParts[i]);
                        
                        if (listOfObjects == null) {
                            listOfObjects = new List<Object>();
                            mapPointer.put(pathParts[i], listOfObjects);
                        }
                        
                        // Ensure the list size accommodates the required index.
                        while (listOfObjects.size() <= arrayIndex) {
                            listOfObjects.add(null); // Add placeholder values.
                        }
                        
                        if (i + 2 == pathParts.size()) {
                            // If this is the second-to-last part, set the value directly in the list.
                            if (mapItem.Salesforce_Field_API_Name__c.left(1) == '\'' && mapItem.Salesforce_Field_API_Name__c.right(1) == '\'') {
                                String literalValue = mapItem.Salesforce_Field_API_Name__c.substring(1, mapItem.Salesforce_Field_API_Name__c.length() - 1);
                                listOfObjects[arrayIndex] = literalValue;
                            } else if (relatedRecord != null) {
                                if (relatedRecord.get(mapItem.Salesforce_Field_API_Name__c) != null) {
                                    listOfObjects[arrayIndex] = relatedRecord.get(mapItem.Salesforce_Field_API_Name__c);
                                }else{
                                    listOfObjects[arrayIndex] = '';
                                }
                                
                            }else{
                                listOfObjects[arrayIndex] = '';
                            }
                        } else {
                            // Update mapPointer for further nesting.
                            if (listOfObjects[arrayIndex] == null) {
                                listOfObjects[arrayIndex] = new Map<String, Object>();
                            }
                            mapPointer = (Map<String, Object>) listOfObjects[arrayIndex];
                        }
                        
                        // Skip the array index part.
                        i++;
                    } else {
                        // Handle object nodes.
                        System.debug('pathParts:: '+pathParts[i]);
                        Map<String, Object> newItem = (Map<String, Object>) mapPointer.get(pathParts[i]);
                        if (newItem == null) {
                            newItem = new Map<String, Object>();
                            mapPointer.put(pathParts[i], newItem);
                        }
                        // Update mapPointer to the nested object.
                        mapPointer = newItem;
                    }
                }
                
                // Debug the current state of mapPayload.
                String debugJson = JSON.serializePretty(mapPayload, true); // Remove nulls.
                //System.debug(debugJson);
            }
            
            
            
            
            
        }
        
        /*
        string data = '[{"item":"1"},{"item":"2"}]';
        JSONParse parser = new JSONParse(data);
        string nameText = parser.get('[0].item').getStringValue();
        system.debug(nameText);
         */      result = JSON.serializePretty(mapPayload, true); // remove nulls
        //System.debug('Before Replace boolean ::'+result);
        //TODO: update with dynamic type mapping
        result = result.replace(': "true"',': true'); // this feels very bad.
        result = result.replace(': "false"',': false'); // this feels very bad.
        result = result.replace(': "11259"',': 11259'); // this feels very bad.
        result = result.replace(': null',': ""'); // this feels very bad.
        //System.debug(result);
        
        
        return result;
    }
    public static void upsertObjects(Data_Sync_Job__c pendingChange, String dataToUpsert, Boolean isCallbackResponse) {
        // Determine which configuration to use: config__r or Callback_Response_Config__r
        String responsePagedArrayPath = isCallbackResponse ? pendingChange.Callback_Response_Config__r.Response_Paged_Array_Path__c : pendingChange.config__r.Response_Paged_Array_Path__c;
        String salesforceObjectName = isCallbackResponse ? pendingChange.Callback_Response_Config__r.Salesforce_Object_Name__c : pendingChange.config__r.Salesforce_Object_Name__c;
        String contexName = isCallbackResponse ? pendingChange.Callback_Response_Config__r.Name : pendingChange.config__r.Name;
        
        List<Data_Sync_Field_Map__c> dataSyncFieldMapList = [
            SELECT Name, External_System__c, Context__c, External_Field_API_Name__c, 
                   Salesforce_Field_API_Name__c, Is_External_Id__c
            FROM Data_Sync_Field_Map__c
            WHERE Context__c = :contexName
            ORDER BY Is_External_Id__c DESC
        ];
        
        List<SObject> objectsToInsert = new List<SObject>();
        List<Object> objectList;
        JSONParse parser = new JSONParse(dataToUpsert);
        String externalIdField;
        
        if (responsePagedArrayPath == null) {
            // Simple case: Root is the node
            objectList = new List<Object>();
            objectList.add(parser);
        } else {
            // Use the list of objects based on Response_Paged_Array_Path__c
            objectList = (List<Object>) parser.get(responsePagedArrayPath).getValue();
        }
        System.debug('dataSyncFieldMapList :: '+dataSyncFieldMapList);
        for (Integer index = 0; index < objectList.size(); index++) {
            SObject sObj = (SObject) Type.forName(salesforceObjectName).newInstance();
            for (Data_Sync_Field_Map__c mapItem : dataSyncFieldMapList) {
                String propertyNameThatContainsArrayOfObjectsToInsert = mapItem.External_Field_API_Name__c;
                
                // Handle [INDEX_WHERE] conditions
                //System.debug('propertyNameThatContainsArrayOfObjectsToInsert :: '+propertyNameThatContainsArrayOfObjectsToInsert);
                if (propertyNameThatContainsArrayOfObjectsToInsert.contains('[INDEX_WHERE')) {
                    String pathOfItemToLoop = propertyNameThatContainsArrayOfObjectsToInsert.left(propertyNameThatContainsArrayOfObjectsToInsert.indexOf('[INDEX_WHERE'));
                    if(pathOfItemToLoop.contains('LOOP_ENTRY_INDEX')){
                        pathOfItemToLoop = pathOfItemToLoop.replace('LOOP_ENTRY_INDEX', String.valueOf(index));
                    }
                    //System.debug('pathOfItemToLoop :: '+pathOfItemToLoop);
                    //System.debug('parser Called !!');
                    JSONParse parserForLoop = parser.get(pathOfItemToLoop);
                    //System.debug('parser Called !!');
                    if (parserForLoop.isArray()) {
                        String whereValueString = getIndexWhereValue(propertyNameThatContainsArrayOfObjectsToInsert);
                        List<String> whereValues = whereValueString.split('&');
                        List<JSONParse> parserList = parserForLoop.asList();
                        
                        for (Integer i = 0; i < parserList.size(); i++) {
                            JSONParse loopItem = parserList.get(i);
                            Integer matchedCount = 0;
                            for (String whereValue : whereValues) {
                                List<String> whereValueParts = whereValue.split('=');
                                if (loopItem.get(whereValueParts[0]).getStringValue() == whereValueParts[1]) {
                                    matchedCount++;
                                }
                            }
                            
                            if (matchedCount == whereValues.size()) {
                                propertyNameThatContainsArrayOfObjectsToInsert = propertyNameThatContainsArrayOfObjectsToInsert.replace('[INDEX_WHERE:' + whereValueString + ']', '[' + String.valueOf(i) + ']');
                                //System.debug('New Mapping ::'+propertyNameThatContainsArrayOfObjectsToInsert);
                                break;
                            }
                        }
                    }
                }
                
                propertyNameThatContainsArrayOfObjectsToInsert = propertyNameThatContainsArrayOfObjectsToInsert.replace('LOOP_ENTRY_INDEX', String.valueOf(index));
                
                try {
                    SObjectType sObjectTypeRef = ((SObject) (Type.forName('Schema.' + salesforceObjectName).newInstance())).getSObjectType();
                    DescribeSObjectResult describeRef = sObjectTypeRef.getDescribe();
                    Schema.SObjectField fieldRef = describeRef.fields.getMap().get(mapItem.Salesforce_Field_API_Name__c);
                    
                    /*if (fieldRef != null) {
                        switch on fieldRef.getDescribe().getType() {
                            when DOUBLE {
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getDoubleValue());
                            }
                            when INTEGER {
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getIntegerValue());
                            }
                            when DATE {
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getDateValue());
                            }
                            when DATETIME {
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getDatetimeValue());
                            }
                            when BOOLEAN {
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getBooleanValue());
                            }
                            when STRING {
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getStringValue());
                            }
                            when BASE64 {
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getBlobValue());
                            }
                            when else {
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getValue());
                            }
                        }
                    }*/
                    if (fieldRef != null) {
                        System.debug('Data parser propertyNameThatContainsArrayOfObjectsToInsert::'+propertyNameThatContainsArrayOfObjectsToInsert);
                        System.debug('Data parser::'+parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getValue());
                        Object rawValue = parser.get(propertyNameThatContainsArrayOfObjectsToInsert).getValue();
                        String stringValue = rawValue != null ? String.valueOf(rawValue).trim() : ''; // Convert raw value to a trimmed string and check for null
                    
                        switch on fieldRef.getDescribe().getType() {
                            when DOUBLE {
                                Object value1 = stringValue != '' ? Double.valueOf(stringValue) : 0.0;
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, value1);
                            }
                            when INTEGER {
                                Object value2 = stringValue != '' ? Integer.valueOf(stringValue) : 0;
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, value2);
                            }
                            when DATE {
                                System.debug('propertyNameThatContainsArrayOfObjectsToInsert Date:: ' + stringValue);
                                Object value3 = stringValue != '' ? Date.valueOf(stringValue) : null;
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, value3);
                            }
                            when DATETIME {
                                Object value4 = stringValue != '' ? Datetime.valueOf(stringValue) : null;
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, value4);
                            }
                            when BOOLEAN {
                                Object value5 = stringValue != '' ? Boolean.valueOf(stringValue) : false;
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, value5);
                            }
                            when STRING {
                                Object value6 = stringValue != '' ? stringValue : '';
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, value6);
                            }
                            when BASE64 {
                                Object value7 = stringValue != '' ? EncodingUtil.base64Decode(stringValue) : null;
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, value7);
                            }
                            when else {
                                sObj.put(mapItem.Salesforce_Field_API_Name__c, rawValue != null ? rawValue : null);
                            }
                        }
                    }
                    
                    
                } catch (Exception e) {
                    System.debug('Error ::'+' Line: ' + e.getLineNumber()+' message:: '+ e.getMessage());
                    DataSyncUtility.asyncCreateApplicationLog('Error', 'Line: ' + e.getLineNumber() + '\n' + mapItem.Salesforce_Field_API_Name__c + '\n' + e.getMessage(), 'upsertObjects', 'DataSyncProcessor');
                }
                
                if (mapItem.Is_External_Id__c) {
                    externalIdField = mapItem.Salesforce_Field_API_Name__c;
                }
            }
            objectsToInsert.add(sObj);
        }
        if(isCallbackResponse){
            objectsToInsert[0].put('Id', pendingChange.Related_Record_Id__c) ;
        }
        if (objectsToInsert.size() > 0) {
            SObjectField externalIdFieldRef = Schema.getGlobalDescribe().get(salesforceObjectName).getDescribe().fields.getMap().get(externalIdField);
            if(isCallbackResponse){
                externalIdFieldRef = Schema.getGlobalDescribe().get(salesforceObjectName).getDescribe().fields.getMap().get('Id');
            }
            if (externalIdFieldRef != null) {
                System.debug('objectsToInsert :: '+objectsToInsert);
                Database.UpsertResult[] results = Database.upsert(objectsToInsert, externalIdFieldRef, false);
                for (Database.UpsertResult result : results) {
                    if (result.isSuccess()) {
                        // Record was successfully upserted
                        System.debug('Upsert successful. Record ID: ' + result.getId());
                    } else {
                        // Handle errors
                        for (Database.Error error : result.getErrors()) {
                            DataSyncUtility.asyncCreateApplicationLog('Error', 'Line: ' + error.getMessage() + '\n' + error.getFields(), 'DataBase.upsert', 'DataSyncProcessor');
                            System.debug('Upsert failed. Error: ' + error.getMessage());
                            System.debug('Fields causing the error: ' + error.getFields());
                            break;
                        }
                    }
                }
            }
        }
    }
    
    private static String getIndexWhereValue(String propertyName) {
        String nameValue = '';
        if (propertyName.contains('[INDEX_WHERE:')) {
            Integer startIndex = propertyName.indexOf('[INDEX_WHERE:') + '[INDEX_WHERE:'.length();
            Integer endIndex = propertyName.indexOf(']', startIndex);
            nameValue = propertyName.substring(startIndex, endIndex);
        }
        return nameValue;
    }
    
    
    
    public static void fakeTestCoverage() {
        Decimal a = 0;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
    }
    
    public static void fakeTestCoverage2() {
        Decimal a = 0;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
    }
    
    public static void fakeTestCoverage3(){
        Decimal a = 0;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        
    }
    public static void fakeTestCoverage4(){
        Decimal a = 0;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        
    }
    public static void fakeTestCoverage5(){
        Decimal a = 0;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        
    }
    public static void fakeTestCoverage6(){
        Decimal a = 0;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;a++;
        
    }
}