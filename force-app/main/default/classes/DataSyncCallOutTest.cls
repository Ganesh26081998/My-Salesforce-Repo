@IsTest
private class DataSyncCallOutTest {
    @IsTest
    static void testCallDataSyncCallOut() {
        Test.startTest();

        DataSyncCallOut callOut = new DataSyncCallOut();
        callOut.setNamedCredentialPrefix('WellSky');

        HttpResponse response = callOut.callDataSyncCallOut('GET', '/v1/patients', null);
        System.assertEquals(0, response.getStatusCode());
        System.assertEquals('', response.getBody());
        
        Test.stopTest();
    }     
}