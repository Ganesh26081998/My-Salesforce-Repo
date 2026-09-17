public inherited sharing class QuickBooksAuthService {
    private static final Integer REQUEST_TIMEOUT_MS = 60000;
    private static final String METHOD_GET = 'GET';
    private static final String METHOD_POST = 'POST';
    private static final String METHOD_PUT = 'PUT';

    public static Boolean isTestMode = false;

    // Cache metadata records in memory, keyed by lower-case city name
    @TestVisible
    private static Map<String, QuickBooks_Location_Setting__mdt> locationSettingsMap;

    private static Map<String, QuickBooks_Location_Setting__mdt> getLocationSettings() {
        if (locationSettingsMap == null) {
            locationSettingsMap = new Map<String, QuickBooks_Location_Setting__mdt>();
            for (QuickBooks_Location_Setting__mdt setting : QuickBooks_Location_Setting__mdt.getAll().values()) {
                locationSettingsMap.put(setting.MasterLabel.trim().toLowerCase(), setting);
            }
        }
        return locationSettingsMap;
    }

    private static QuickBooks_Location_Setting__mdt getSettingForLocation(String location) {
        if (String.isBlank(location)) {
            throw new QuickBooksException('Location is required.');
        }

        QuickBooks_Location_Setting__mdt setting = getLocationSettings().get(location.trim().toLowerCase());
        if (setting == null) {
            throw new QuickBooksException('No QuickBooks configuration found for location: ' + location);
        }
        return setting;
    }

    public static HttpResponse makeApiCall(String endpoint, String method, String body, String location) {
        if (isTestMode) {
            return buildMockResponse();
        }

        try {
            validateRequest(endpoint, method, location);

            HttpRequest request = new HttpRequest();
            request.setEndpoint(buildEndpoint(endpoint, location));
            request.setMethod(method);
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('Accept', 'application/json');
            request.setTimeout(REQUEST_TIMEOUT_MS);

            if (shouldSetBody(method, body)) {
                request.setBody(body);
            }

            HttpResponse response = new Http().send(request);
            System.debug(
                LoggingLevel.INFO,
                'QuickBooks API call completed. Location=' + location + ', Status=' + response.getStatusCode()
            );
            return response;
        } catch (Exception e) {
            throw new QuickBooksException('API Call failed: ' + e.getMessage());
        }
    }

    public static HttpResponse makeApiCall(String endpoint, String method, String body) {
        throw new QuickBooksException('Location-based API call required. Use makeApiCall(endpoint, method, body, location)');
    }

    public static String getRealmId(String location) {
        return getSettingForLocation(location).Realm_ID__c;
    }

    private static void validateRequest(String endpoint, String method, String location) {
        if (String.isBlank(endpoint)) {
            throw new QuickBooksException('Endpoint is required for API calls');
        }

        if (String.isBlank(method)) {
            throw new QuickBooksException('HTTP method is required for API calls');
        }

        if (String.isBlank(location)) {
            throw new QuickBooksException('Location is required for API calls');
        }
    }

    private static String buildEndpoint(String endpoint, String location) {
        QuickBooks_Location_Setting__mdt setting = getSettingForLocation(location);
        
        // Uses the Named Credential Key defined in CMDT (e.g. Madison points to Milwaukee's credential)
        String credentialKey = String.isNotBlank(setting.Named_Credential_Key__c) 
            ? setting.Named_Credential_Key__c 
            : location;

        return QuickBooksCredentialManager.getNamedCredentialURL(credentialKey) + '/' + setting.Realm_ID__c + endpoint;
    }

    private static Boolean shouldSetBody(String method, String body) {
        return String.isNotBlank(body) && (method.equalsIgnoreCase(METHOD_POST) || method.equalsIgnoreCase(METHOD_PUT));
    }

    private static HttpResponse buildMockResponse() {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setHeader('Content-Type', 'application/json');
        response.setBody('{"Invoice":{"Id":"123","Line":[{"Id":"1","DetailType":"SalesItemLineDetail"}]}}');
        return response;
    }
}