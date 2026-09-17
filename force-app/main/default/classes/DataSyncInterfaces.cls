public class DataSyncInterfaces {
    public interface IDataSyncCallOut {
        void setNamedCredentialPrefix(String prefix);
        String getNamedCredential();
        String buildPayload(Map<String, Object> input);
        HttpResponse execute(String method, String endpoint, String requestBody);        
    }

    public interface IDataSyncProcessor {
        void processSync(Data_Sync_Job__c pendingChange);
    }

}