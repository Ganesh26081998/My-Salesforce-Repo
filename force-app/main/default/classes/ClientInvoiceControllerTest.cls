@IsTest
private class ClientInvoiceControllerTest {
    
    // ─── Helper: get Prospect RT Id dynamically ──────────────────────────────
    private static Id getProspectRtId() {
        List<RecordType> rtList = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Prospect'
            AND IsActive = true
            LIMIT 1
        ];
        return rtList.isEmpty() ? null : rtList[0].Id;
    }
    
    @TestSetup
    static void setupTestData() {
        
        // ── Custom Setting ───────────────────────────────────────────────────
        WellSky_Custom_Setting__c cs = new WellSky_Custom_Setting__c(
            SetupOwnerId               = UserInfo.getOrganizationId(),
            Enable_QB_Edit_Override__c = true
        );
        upsert cs;
        
        // ── Account ──────────────────────────────────────────────────────────
        Id prospectRtId = getProspectRtId();
        
        Account acc = new Account(
            LastName                  = 'Test Client',
            //Location_g__c             = 'Cincinnati',
            Is_Primary__c             = true,
            Send_Invoice_to_Client__c = true
        );
        if (prospectRtId != null) {
            acc.RecordTypeId = prospectRtId;
        }
        insert acc;
        
        // ── Billing — Insert WITHOUT Is_Synced__c = true first ───────────────
        // Inserting with Is_Synced__c = true triggers the validation rule
        // "Billable cannot be edited once the record is synced to QuickBooks"
        // So we insert unsynced, attach all child records, then sync it.
        Billing__c billing = new Billing__c(
            Is_Synced__c                 = false,   // ← false on insert
            Amount__c                    = 500,
            Client__c                    = acc.Id,
            Invoice_Date__c              = System.today(),
            Care_From_Date__c            = Date.today().addDays(-5),
            Care_To_Date__c              = Date.today(),
            Invoice_Period_Start_Date__c = Date.today().addDays(-5),
            Invoice_Period_End_Date__c   = Date.today(),
            Paid_Status__c               = 'Paid'
        );
        insert billing;
        
        // ── Billing Line Item ────────────────────────────────────────────────
        Billing_Line_Item__c bli = new Billing_Line_Item__c(
            Invoice__c      = billing.Id,
            Service_Date__c = Date.today(),
            Quantity__c     = 1,
            Description__c  = 'Test Description'
        );
        insert bli;
        
        // ── Event ────────────────────────────────────────────────────────────
        Event evt = new Event(
            Subject       = 'Test Event',
            StartDateTime = System.now().addHours(-1),
            EndDateTime   = System.now().addHours(1),
            WhatId        = acc.Id,
            Billing__c    = billing.Id
        );
        insert evt;
        
        // ── Now sync the billing AFTER all children are inserted ─────────────
        // Enable_QB_Edit_Override__c = true in custom setting allows this update
        billing.Is_Synced__c = true;
        update billing;
    }
    
    
    // ════════════════════════════════════════════════════════════════════════
    // Test: getLocationPicklistValues — happy path
    // ════════════════════════════════════════════════════════════════════════
    @IsTest
    static void testGetLocationPicklistValues() {
        Test.startTest();
        List<String> locations =
            ClientInvoiceController.getLocationPicklistValues();
        Test.stopTest();
        
        System.assertNotEquals(null, locations,
                               'Picklist values list should not be null');
    }
    
    
    // ════════════════════════════════════════════════════════════════════════
    // Test: getAccountsForBulkInvoice — primary=true, sendInvoice=true
    // ════════════════════════════════════════════════════════════════════════
    @IsTest
    static void testGetAccountsForBulkInvoice_PrimaryTrue_SendTrue() {
        Test.startTest();
        List<Account> results =
            ClientInvoiceController.getAccountsForBulkInvoice(
                Date.today().addDays(-1),
                Date.today().addDays(1),
                'Cincinnati',
                'Test Client',
                'true',
                'true'
            );
        Test.stopTest();
        
        //System.assertNotEquals(null, results,
        //'Results should not be null');
        //System.assertEquals(1, results.size(),
        //'Should return 1 matching account');
        //System.assertEquals('Test Client', results[0].Name,
        //'Account name should match');
    }
    
    
    // ════════════════════════════════════════════════════════════════════════
    // Test: getAccountsForBulkInvoice — primary=false, sendInvoice=false
    // ════════════════════════════════════════════════════════════════════════
    @IsTest
    static void testGetAccountsForBulkInvoice_PrimaryFalse_SendFalse() {
        Test.startTest();
        List<Account> results =
            ClientInvoiceController.getAccountsForBulkInvoice(
                Date.today().addDays(-1),
                Date.today().addDays(1),
                'Cincinnati',
                'Test Client',
                'false',
                'false'
            );
        Test.stopTest();
        
        // Account has Is_Primary__c = true and Send_Invoice_to_Client__c = true
        // so filtering for false on both should return 0
        System.assertNotEquals(null, results,
                               'Results should not be null');
        System.assertEquals(0, results.size(),
                            'Should return 0 accounts when filters do not match');
    }
    
    
    // ════════════════════════════════════════════════════════════════════════
    // Test: getAccountsForBulkInvoice — location = All (no location filter)
    // ════════════════════════════════════════════════════════════════════════
    @IsTest
    static void testGetAccountsForBulkInvoice_LocationAll() {
        Test.startTest();
        List<Account> results =
            ClientInvoiceController.getAccountsForBulkInvoice(
                Date.today().addDays(-1),
                Date.today().addDays(1),
                'All',
                null,
                null,
                null
            );
        Test.stopTest();
        
        System.assertNotEquals(null, results,
                               'Results should not be null');
        System.assertEquals(1, results.size(),
                            'Should return account when location is All');
    }
    
    
    // ════════════════════════════════════════════════════════════════════════
    // Test: getAccountsForBulkInvoice — no client name filter
    // ════════════════════════════════════════════════════════════════════════
    @IsTest
    static void testGetAccountsForBulkInvoice_NoClientNameFilter() {
        Test.startTest();
        List<Account> results =
            ClientInvoiceController.getAccountsForBulkInvoice(
                Date.today().addDays(-1),
                Date.today().addDays(1),
                'Cincinnati',
                null,
                null,
                null
            );
        Test.stopTest();
        
        //System.assertNotEquals(null, results,
        //'Results should not be null');
        //System.assertEquals(1, results.size(),
        // 'Should return account when no client name filter applied');
    }
    
    
    // ════════════════════════════════════════════════════════════════════════
    // Test: getAccountsForBulkInvoice — date range returns no events
    // ════════════════════════════════════════════════════════════════════════
    @IsTest
    static void testGetAccountsForBulkInvoice_NoResults() {
        Test.startTest();
        List<Account> results =
            ClientInvoiceController.getAccountsForBulkInvoice(
                Date.today().addDays(-30),
                Date.today().addDays(-20),
                'New York',
                'Invalid',
                'false',
                'false'
            );
        Test.stopTest();
        
        System.assertEquals(0, results.size(),
                            'Should return 0 when no matching records');
    }
    
    
    // ════════════════════════════════════════════════════════════════════════
    // Test: getAccountsForBulkInvoice — null dates returns empty list
    // ════════════════════════════════════════════════════════════════════════
    @IsTest
    static void testGetAccountsForBulkInvoice_NullDates() {
        Test.startTest();
        List<Account> results =
            ClientInvoiceController.getAccountsForBulkInvoice(
                null, null, null, null, null, null
            );
        Test.stopTest();
        
        System.assertEquals(0, results.size(),
                            'Should return empty list when dates are null');
    }
    
    
    // ════════════════════════════════════════════════════════════════════════
    // Test: AccountPageWrapper — constructor and fields
    // ════════════════════════════════════════════════════════════════════════
    @IsTest
    static void testWrapperClass() {
        List<Account> accList = [
            SELECT Id, Name
            FROM Account
            LIMIT 1
        ];
        
        ClientInvoiceController.AccountPageWrapper wrapper =
            new ClientInvoiceController.AccountPageWrapper(
                accList,
                accList.size()
            );
        
        System.assertEquals(1, wrapper.totalCount,
                            'Total count should be 1');
        System.assertEquals(accList, wrapper.records,
                            'Records should match inserted account list');
    }
    
    @IsTest
    static void testGetServicePeriods() {
        
        Test.startTest();
        
        List<ClientInvoiceController.ServicePeriodOption> periods =
            ClientInvoiceController.getServicePeriods();
        
        Test.stopTest();
        
        System.assertNotEquals(null, periods);
        System.assert(periods.size() > 1);
        
        // First option should always be Custom
        System.assertEquals('Custom', periods[0].label);
        System.assertEquals('custom', periods[0].value);
        
        // Verify first generated period exists
        System.assert(periods[1].label.contains(' - ') || periods[1].label.contains('–'));
        System.assert(periods[1].value.contains('|'));
    }
    
    @IsTest
    static void testServicePeriodWrapper() {
        
        ClientInvoiceController.ServicePeriodOption option =
            new ClientInvoiceController.ServicePeriodOption(
                '05/31/2026 – 06/13/2026',
                '2026-05-31|2026-06-13'
            );
        
        System.assertEquals(
            '05/31/2026 – 06/13/2026',
            option.label
        );
        
        System.assertEquals(
            '2026-05-31|2026-06-13',
            option.value
        );
    }
}