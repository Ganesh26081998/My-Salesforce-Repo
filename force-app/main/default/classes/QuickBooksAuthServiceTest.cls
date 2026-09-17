@isTest
public class QuickBooksAuthServiceTest {

    // ─── Metadata Injection Helper ───────────────────────────────────────────
    // This removes the dependency on live Production data and Custom Labels!
    private static void injectMockMetadata() {
        QuickBooksAuthService.locationSettingsMap = new Map<String, QuickBooks_Location_Setting__mdt>{
            'detroit' => new QuickBooks_Location_Setting__mdt(MasterLabel = 'Detroit', Named_Credential_Key__c = 'Detroit', Realm_ID__c = '11111'),
            'milwaukee' => new QuickBooks_Location_Setting__mdt(MasterLabel = 'Milwaukee', Named_Credential_Key__c = 'Milwaukee', Realm_ID__c = '22222'),
            'cincinnati' => new QuickBooks_Location_Setting__mdt(MasterLabel = 'Cincinnati', Named_Credential_Key__c = 'Cincinnati', Realm_ID__c = '33333')
        };
    }

    // ─── Mocks ───────────────────────────────────────────────────────────────
    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"Invoice":{"Id":"123","Line":[{"Id":"1","DetailType":"SalesItemLineDetail"}]}}');
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Simulated network failure');
        }
    }

    // ─── getRealmId() ────────────────────────────────────────────────────────

    @isTest
    static void testGetRealmId_ValidLocations() {
        injectMockMetadata();
        Test.startTest();
        // Asserting against our injected mock data instead of Custom Labels
        System.assertEquals('11111', QuickBooksAuthService.getRealmId('Detroit'));
        System.assertEquals('22222', QuickBooksAuthService.getRealmId('Milwaukee'));
        System.assertEquals('33333', QuickBooksAuthService.getRealmId('Cincinnati'));
        Test.stopTest();
    }

    @isTest
    static void testGetRealmId_NullLocation() {
        try {
            QuickBooksAuthService.getRealmId(null);
            System.assert(false, 'Expected exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Location is required'), e.getMessage());
        }
    }

    @isTest
    static void testGetRealmId_EmptyLocation() {
        try {
            QuickBooksAuthService.getRealmId('');
            System.assert(false, 'Expected exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Location is required'), e.getMessage());
        }
    }

    @isTest
    static void testGetRealmId_UnknownLocation() {
        injectMockMetadata();
        try {
            QuickBooksAuthService.getRealmId('Chicago');
            System.assert(false, 'Expected exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('No QuickBooks configuration found'), e.getMessage());
        }
    }

    // ─── 3-arg overload ──────────────────────────────────────────────────────

    @isTest
    static void testOverloadedMakeApiCall_ThrowsAlways() {
        try {
            QuickBooksAuthService.makeApiCall('/invoice', 'POST', '{}');
            System.assert(false, 'Expected exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Location-based API call required'), e.getMessage());
        }
    }

    // ─── makeApiCall() location validation ───────────────────────────────────

    @isTest
    static void testMakeApiCall_NullLocation_ThrowsException() {
        try {
            QuickBooksAuthService.makeApiCall('/invoice', 'POST', '{}', null);
            System.assert(false, 'Expected exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Location is required'), e.getMessage());
        }
    }

    @isTest
    static void testMakeApiCall_EmptyLocation_ThrowsException() {
        try {
            QuickBooksAuthService.makeApiCall('/invoice', 'POST', '{}', '');
            System.assert(false, 'Expected exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Location is required'), e.getMessage());
        }
    }

    @isTest
    static void testMakeApiCall_UnknownLocation_ThrowsException() {
        injectMockMetadata();
        try {
            QuickBooksAuthService.makeApiCall('/invoice', 'POST', '{}', 'Chicago');
            System.assert(false, 'Expected exception');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('No QuickBooks configuration found'), e.getMessage());
        }
    }

    // ─── makeApiCall() HTTP success paths ────────────────────────────────────

    @isTest
    static void testMakeApiCall_POST_Detroit() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/invoice', 'POST', '{"Name":"Detroit Invoice"}', 'Detroit');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
        System.assert(res.getBody().contains('Invoice'));
    }

    @isTest
    static void testMakeApiCall_POST_Milwaukee() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/invoice', 'POST', '{"Name":"Milwaukee Invoice"}', 'Milwaukee');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
    }

    @isTest
    static void testMakeApiCall_POST_Cincinnati() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/invoice', 'POST', '{"Name":"Cincinnati Invoice"}', 'Cincinnati');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
    }

    @isTest
    static void testMakeApiCall_PUT() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/invoice/123', 'PUT', '{"Name":"Updated"}', 'Detroit');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
    }

    @isTest
    static void testMakeApiCall_GET_NoBody() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/invoice/123', 'GET', null, 'Detroit');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
    }

    @isTest
    static void testMakeApiCall_DELETE_NoBody() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/invoice/123', 'DELETE', null, 'Detroit');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
    }

    @isTest
    static void testMakeApiCall_LowercaseMethod() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/invoice', 'post', '{"Name":"Test"}', 'Detroit');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
    }

    @isTest
    static void testMakeApiCall_QueryEndpoint() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/query?query=SELECT+*+FROM+Invoice', 'GET', null, 'Milwaukee');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
    }

    @isTest
    static void testMakeApiCall_CustomerEndpoint() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/customer', 'POST', '{"DisplayName":"Test Customer"}', 'Cincinnati');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
    }

    // ─── makeApiCall() network exception → wrapped as QuickBooksException ────

    @isTest
    static void testMakeApiCall_NetworkException_Wrapped() {
        injectMockMetadata();
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        Test.startTest();
        try {
            QuickBooksAuthService.makeApiCall('/invoice', 'POST', '{}', 'Detroit');
            System.assert(false, 'Expected QuickBooksException');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('API Call failed'), e.getMessage());
            System.assert(e.getMessage().contains('Simulated network failure'), e.getMessage());
        }
        Test.stopTest();
    }

    // ─── isTestMode flag behaviour ────────────────────────────────────────────

    @isTest
    static void testIsTestMode_ReturnsSyntheticResponse() {
        QuickBooksAuthService.isTestMode = true;
        Test.startTest();
        HttpResponse res = QuickBooksAuthService.makeApiCall(
            '/invoice', 'POST', '{}', 'Detroit');
        Test.stopTest();
        System.assertEquals(200, res.getStatusCode());
        System.assert(res.getBody().contains('Invoice'));
        QuickBooksAuthService.isTestMode = false; // reset
    }
}