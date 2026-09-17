/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : QuickBooksCustomerService
CreatedOn     : 13-12-2025
LastModifiedOn: 22-06-2026
LastModifiedBy: Rohit Dhote
Description   : Builds QuickBooks Customer payloads from Salesforce Accounts,
                creates or updates Customers in QuickBooks, and returns the
                QuickBooks Customer Id for Salesforce.
                Per-location Customer IDs are stored in QB_Customer_Location__c
                child object instead of directly on the Account.
----------------------------------------------------------------------------
*/

public inherited sharing class QuickBooksCustomerService {
    private static final String CUSTOMER_ENDPOINT = '/customer?minorversion=65';
    private static final String DUPLICATE_NAME_CODE = '6240';
    private static final String OBJECT_NOT_FOUND_CODE = '610';

    public static String createOrUpdateCustomer(Account account, String location) {
        try {
            validateInput(account, location);

            // ── CHANGED: look up per-location ID instead of account field ──
            String quickBooksCustomerId = getCustomerIdForLocation(account.Id, location);

            if (String.isBlank(quickBooksCustomerId)) {
                quickBooksCustomerId = queryCustomerByName(account.Name, location);
            }

            Map<String, Object> customerMap = buildCustomerMap(account);

            if (String.isNotBlank(quickBooksCustomerId)) {
                return updateCustomerWithAutoHeal(quickBooksCustomerId, customerMap, location, account);
            }

            return safeCreateCustomer(customerMap, location, account);
        } catch (Exception e) {
            throw new QuickBooksException('Error creating/updating customer: ' + e.getMessage());
        }
    }

    // ── NEW: fetch QB Customer ID for a specific location ──────────────────
    public static String getCustomerIdForLocation(Id accountId, String location) {
        List<QB_Customer_Location__c> records = [
            SELECT QB_Customer_Id__c
            FROM QB_Customer_Location__c
            WHERE Account__c = :accountId
            AND Location__c = :location
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0].QB_Customer_Id__c;
    }

    // ── NEW: upsert the per-location QB Customer ID ─────────────────────────
    public static void saveCustomerIdForLocation(Id accountId, String location, String customerId) {
        List<QB_Customer_Location__c> existing = [
            SELECT Id
            FROM QB_Customer_Location__c
            WHERE Account__c = :accountId
            AND Location__c = :location
            LIMIT 1
        ];

        QB_Customer_Location__c record = existing.isEmpty()
            ? new QB_Customer_Location__c(Account__c = accountId, Location__c = location)
            : existing[0];

        record.QB_Customer_Id__c = customerId;
        upsert record;
    }

    private static void validateInput(Account account, String location) {
        if (String.isBlank(location)) {
            throw new QuickBooksException('Location is required for customer sync');
        }

        if (account == null || account.Id == null) {
            throw new QuickBooksException('Account is required for customer sync');
        }
    }

    private static Map<String, Object> buildCustomerMap(Account account) {
        Map<String, Object> customerMap = new Map<String, Object>{
            'DisplayName' => buildDisplayName(account),
            'CompanyName' => account.Name,
            'AcctNum' => account.Id
        };

        if (String.isNotBlank(account.Mobile_Phones__c)) {
            customerMap.put('PrimaryPhone', new Map<String, Object>{ 'FreeFormNumber' => account.Mobile_Phones__c });
        }

        if (String.isNotBlank(account.PersonEmail)) {
            customerMap.put('PrimaryEmailAddr', new Map<String, Object>{ 'Address' => account.PersonEmail });
        }

        Map<String, Object> billingAddress = buildBillingAddress(account);
        if (!billingAddress.isEmpty()) {
            customerMap.put('BillAddr', billingAddress);
        }
        customerMap.put('ShipAddr', new Map<String, Object>{ 'Line1' => '' });

        return customerMap;
    }

    private static Map<String, Object> buildBillingAddress(Account account) {
        Map<String, Object> billingAddress = new Map<String, Object>();

        if (String.isNotBlank(account.Address__Street__s)) {
            billingAddress.put('Line1', account.Address__Street__s);
        }

        if (String.isNotBlank(account.Address__City__s)) {
            billingAddress.put('City', account.Address__City__s);
        }

        if (String.isNotBlank(account.Address__PostalCode__s)) {
            billingAddress.put('PostalCode', account.Address__PostalCode__s);
        }

        if (String.isNotBlank(account.Address__StateCode__s)) {
            billingAddress.put('CountrySubDivisionCode', account.Address__StateCode__s);
        }

        if (String.isNotBlank(account.Address__CountryCode__s)) {
            billingAddress.put('Country', account.Address__CountryCode__s);
        }

        return billingAddress;
    }

    private static String buildDisplayName(Account account) {
        return account.Name + ' - ' + String.valueOf(account.Id).right(4);
    }

    private static String updateCustomerWithAutoHeal(
        String customerId,
        Map<String, Object> customerMap,
        String location,
        Account account
    ) {
        try {
            return updateCustomerInQB(customerId, customerMap, location);
        } catch (Exception e) {
            if (isObjectNotFoundError(e)) {
                removeUpdateFields(customerMap);
                return safeCreateCustomer(customerMap, location, account);
            }

            throw e;
        }
    }

    private static String safeCreateCustomer(Map<String, Object> customerMap, String location, Account account) {
        try {
            return createCustomerInQB(JSON.serialize(customerMap), location);
        } catch (Exception e) {
            if (isDuplicateNameError(e)) {
                customerMap.put('DisplayName', buildUniqueDisplayName(account));
                return createCustomerInQB(JSON.serialize(customerMap), location);
            }

            throw e;
        }
    }

    private static String buildUniqueDisplayName(Account account) {
        Integer randomNumber = Integer.valueOf(Math.floor(Math.random() * 9000)) + 1000;
        return buildDisplayName(account) + '-' + String.valueOf(randomNumber);
    }

    private static void removeUpdateFields(Map<String, Object> customerMap) {
        customerMap.remove('Id');
        customerMap.remove('SyncToken');
        customerMap.remove('sparse');
    }

    private static Boolean isObjectNotFoundError(Exception e) {
        String message = e.getMessage();
        return message != null && (message.contains('Object Not Found') || message.contains(OBJECT_NOT_FOUND_CODE));
    }

    private static Boolean isDuplicateNameError(Exception e) {
        String message = e.getMessage();
        return message != null &&
            (message.contains('Duplicate Name') || message.contains(DUPLICATE_NAME_CODE) || message.contains('already exists'));
    }

    private static String queryCustomerByName(String name, String location) {
        String query = 'select Id from Customer Where DisplayName = \'' + String.escapeSingleQuotes(name) + '\'';
        String endpoint = '/query?query=' + EncodingUtil.urlEncode(query, 'UTF-8');
        HttpResponse response = QuickBooksAuthService.makeApiCall(endpoint, 'GET', null, location);

        if (response.getStatusCode() != 200) {
            return null;
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        Map<String, Object> queryResponse = (Map<String, Object>) responseMap.get('QueryResponse');
        if (queryResponse == null || !queryResponse.containsKey('Customer')) {
            return null;
        }

        List<Object> customers = (List<Object>) queryResponse.get('Customer');
        if (customers.isEmpty()) {
            return null;
        }

        Map<String, Object> customerData = (Map<String, Object>) customers[0];
        return (String) customerData.get('Id');
    }

    private static String createCustomerInQB(String jsonBody, String location) {
        HttpResponse response = QuickBooksAuthService.makeApiCall(CUSTOMER_ENDPOINT, 'POST', jsonBody, location);

        if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
            return getCustomerId(response.getBody());
        }

        throw new QuickBooksException('QB Customer Creation Failed: ' + response.getStatus() + ' - ' + response.getBody());
    }

    private static String updateCustomerInQB(String customerId, Map<String, Object> customerMap, String location) {
        customerMap.put('Id', customerId);
        customerMap.put('SyncToken', getSyncToken(customerId, location));
        customerMap.put('sparse', true);

        HttpResponse response = QuickBooksAuthService.makeApiCall(CUSTOMER_ENDPOINT, 'POST', JSON.serialize(customerMap), location);

        if (response.getStatusCode() == 200) {
            return getCustomerId(response.getBody());
        }

        throw new QuickBooksException('QB Customer Update Failed: ' + response.getStatus() + ' - ' + response.getBody());
    }

    private static String getSyncToken(String customerId, String location) {
        HttpResponse response = QuickBooksAuthService.makeApiCall('/customer/' + customerId + '?minorversion=65', 'GET', null, location);

        if (response.getStatusCode() != 200) {
            return '0';
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        Map<String, Object> customer = (Map<String, Object>) responseMap.get('Customer');
        return customer == null ? '0' : (String) customer.get('SyncToken');
    }

    private static String getCustomerId(String responseBody) {
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> customer = (Map<String, Object>) responseMap.get('Customer');
        return customer == null ? null : (String) customer.get('Id');
    }
}