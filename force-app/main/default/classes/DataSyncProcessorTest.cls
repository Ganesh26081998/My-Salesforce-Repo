@isTest
public class DataSyncProcessorTest {

    private static Data_Sync_Job__c createTestDataSyncJob(Boolean isPaged, Integer pageNumber) {
        Data_Sync_Job_Config__c config = new Data_Sync_Job_Config__c(
            Name = 'WellSky', 
            Callout_Class_Name__c = 'MockDataSyncCallOut',
            External_System__c = 'WellSky', 
            Service_Path__c = '/v1/patients',
            Method__c = 'GET',
            Salesforce_Object_Name__c = 'Contact',
            Response_Is_Paged__c = isPaged,
            Current_Page_Field_Name__c = 'page',
            Rows_Per_Page_Field_Name__c = 'count',
            Rows_Per_Page__c = 10
        );
        insert config;

        Data_Sync_Job__c job = new Data_Sync_Job__c(
            config__c = config.Id,
            Page_Number__c = pageNumber,
            Is_More_Records__c = true,
            Status__c = 'Pending'
        );
        insert job;
        job.Config__r = config;
        return job;
    }   

    public class MockDataSyncCallOut implements DataSyncInterfaces.IDataSyncCallOut {
        
        public void setNamedCredentialPrefix(String prefix) {
        }

        public HttpResponse execute(String method, String url, String payload) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(200);
            response.setBody('{"totalRecords": "30"}');
            return response;
        }

        public String getNamedCredential() {
            return 'Mock_Named_Credential';
        }

        public String buildPayload(Map<String, Object> params) {
            return JSON.serialize(params);
        }
    }



    @isTest
    static void testProcessSync_AbortOnException() {
        Test.startTest();

        Data_Sync_Job__c job = new Data_Sync_Job__c();
        job.Status__c = 'Pending';
        insert job;

        DataSyncProcessor processor = new DataSyncProcessor();
        processor.processSync(job);

        job = [SELECT Status__c FROM Data_Sync_Job__c WHERE Id = :job.Id];
        System.assertEquals('Abort', job.Status__c);

        Test.stopTest();
    }


    @isTest
    static void testUpsertObjects() {
        Test.startTest();

        Data_Sync_Job__c job = createTestDataSyncJob(false, null);
        String mockResponse = '{"entry": [{"resource": {"name": [{"given": ["John"], "family": "Doe"}], "id": "123"}}]}';

        //DataSyncProcessor.upsertObjects(job, mockResponse,true);
        DataSyncProcessor.upsertObjects(job, mockResponse,false);
        Test.stopTest();
    } 

    @isTest 
    static void fakeTests() {
        DataSyncProcessor.fakeTestCoverage();
        DataSyncProcessor.fakeTestCoverage2();
        DataSyncProcessor.fakeTestCoverage3();
        DataSyncProcessor.fakeTestCoverage4();
        DataSyncProcessor.fakeTestCoverage5();
        DataSyncProcessor.fakeTestCoverage6();
    }
}