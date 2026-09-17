public with sharing class DataSyncCallOut implements DataSyncInterfaces.IDataSyncCallOut {
    
    /*
    Example:
    DataSyncCallOut callout = new DataSyncCallOut();
    callout.setNamedCredentialPrefix('WellSky');
    
    HttpResponse response;
    string payload = '';
    //    response = callout.execute('GET', '/v1/patients/?created=gt1800-01-01T00:00&_count=20&_page=0', payload);
    response = callout.execute('GET', '/v1/relatedperson/?patient=6603711&_count=20&_page=0', payload);
    System.Debug(response.getbody());
    
     */
    
    private String namedCredential ;
    // public DataSyncCallOut(String namedCredential) {
        //     retrive named credential from custom object with filter of API Eg. Name = 'WellSky_Production_Named_Credential'
        //     set this.namedCredential with filtered named credential
        //     this.namedCredential = namedCredential;
    // }
    
    private String namedCredentialPrefix;
    
    public void setNamedCredentialPrefix(String prefix) {
        this.namedCredentialPrefix = prefix;
    }
    
    
    
    
    public String getNamedCredential() {
        // For sandboxes and developer editions return the sandbox named credential.
        // This allows for sandboxes to be created with no worry of connecting to production.
        
        Organization orgDetails =  [SELECT IsSandbox, OrganizationType 
                                    FROM Organization 
                                    LIMIT 1][0];
        
        return orgDetails?.IsSandbox || orgDetails?.OrganizationType == 'Developer Edition' ? this.namedCredentialPrefix + '_Sandbox_Named_Credential' : this.namedCredentialPrefix + '_Production_Named_Credential';
    }
    public HttpResponse callDataSyncCallOut(string method, string service, map<string, object> payload) {
        // You can either build the payload yourself or use this function to auto create it.
        string payloadString = DataSyncCallOut.buildPayload(payload);
        return execute(method, service, payloadString);
    }
    //This method is used to make the callout to the external system.
    public HttpResponse execute(string method, string service, string body) {
        HttpResponse response = new HttpResponse();
        try{
            HttpRequest req = new HttpRequest();
            
            this.namedCredential = getNamedCredential();
            string endpoint = 'callout:' + this.namedCredential + service;
            req.setEndpoint(endpoint);
            req.setMethod(method);
            if(body != null && body != '') {
                req.setHeader('Content-Type', 'application/json');  
                req.setBody(body);
            }
            System.debug(endpoint);
            req.setTimeout(120000);
            response = new Http().send(req);
            //system.debug('response: ' + response?.getBody());
        } catch(Exception e){
            system.debug('Line: ' + e.getLineNumber() + '\n' + e.getMessage());
            // TODO: Never all the processor.  Log it yourself.  DataSyncProcessor.asyncCreateApplicationLog('Error','Line: ' + e.getLineNumber() + '\n' + e.getMessage(), 'authenticate', 'FastFieldCallOut');
        }
        return response;
    }
    public static String buildPayload(map<string, object> input) {
        // convert the map into a json string
        return JSON.serialize(input);
    }
    
}