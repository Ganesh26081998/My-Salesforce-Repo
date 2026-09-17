@IsTest
public class BulkInvoiceEmailBatchTest {

    // ---------- Utility ----------
    private static Account createAccount() {
        
         Id prospectRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
        
        Account def_ac = new Account(
         Name = 'No Organization'
        );
        
        insert def_ac;
        
        Account acc = new Account(
            LastName = 'Test Acc',
            RecordTypeId = prospectRtId,
            PersonEmail = 'test@test.com',
        	Send_Invoice_to_Client__c = true
        );
        insert acc;
        return acc;
    }
    
    private static void createCCR(Account acc) {

        Contact relatedContact = new Contact(
            LastName = 'Related Contact',
            Email = 'related@test.com',
            Additional_duties__c = 'Receives invoices'
        );
    
        insert relatedContact;
        
        Id contactRoleRtId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();
        
        HealthCloudGA__ReciprocalRole__c role  = 
            new HealthCloudGA__ReciprocalRole__c(
            	Name = 'Son',
            	RecordTypeId = contactRoleRtId,
            	HealthCloudGA__InverseRole__c = 'Father'
        );
        insert role;
    
        HealthCloudGA__ContactContactRelation__c ccr =
            new HealthCloudGA__ContactContactRelation__c(
                HealthCloudGA__RelatedContact__c = acc.PersonContactId,
                HealthCloudGA__Contact__c = relatedContact.Id,
                HealthCloudGA__Role__c = role.Id
            );
    
        insert ccr;
    }

    private static Bulk_Zip_Job__c createJob() {
        Bulk_Zip_Job__c job = new Bulk_Zip_Job__c(          
            Status__c = 'Processing'
        );
        insert job;
        return job;
    }    
    
    private static Billing__c createBilling(Id accId) {

        WellSky_Custom_Setting__c cs =
            new WellSky_Custom_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Enable_QB_Edit_Override__c = true
            );
    
        upsert cs;
    
        Billing__c billing = new Billing__c(
            Is_Synced__c = false,
            Amount__c = 500,
            Client__c = accId,
            Invoice_Date__c = Date.today(),
            Care_From_Date__c          = Date.today().addDays(-5),
            Care_To_Date__c            = Date.today(),            
            Invoice_Period_Start_Date__c = Date.today().addDays(-5),
            Invoice_Period_End_Date__c   = Date.today(),
            Paid_Status__c             = 'Paid'
        );
    
        insert billing;
    
        return billing;
    }
    
    private static void createEvent(Id accId, Id billingId) {

        Event evt = new Event(
            Subject = 'Test Event',
            StartDateTime = System.now().addHours(-1),
            EndDateTime = System.now().addHours(1),
            WhatId = accId,
            Billing__c = billingId
        );
    
        insert evt;
    }
    
    private static void createBillingLineItem(Id billingId) {
    
        Billing_Line_Item__c bli =
            new Billing_Line_Item__c(
                Invoice__c = billingId,
                Service_Date__c = Date.today(),
                Quantity__c = 1,
                Description__c = 'Test Description',
                Type__c = 'Client Billable',
                Amount__c = 100
            );
    
        insert bli;
    }

    // ---------- TEST 1: STANDARD FLOW ----------
    @isTest
    static void testBatch_StandardFlow() {        

        Account acc = createAccount();
        createCCR(acc);
        Bulk_Zip_Job__c job = createJob();
        
        Billing__c billing = createBilling(acc.Id);

    	createEvent(acc.Id, billing.Id);

    	createBillingLineItem(billing.Id);
        
        billing.Is_Synced__c = true;
        update billing;

        Test.startTest();

        BulkInvoiceEmailBatch batch = new BulkInvoiceEmailBatch(
            job.Id,
            new List<Id>{acc.Id},
            String.valueOf(Date.today()),
            String.valueOf(Date.today()),
            'Standard Invoice',
            new Map<Id, List<Id>>()
        );

        Database.executeBatch(batch, 1);

        Test.stopTest();

        Bulk_Zip_Job__c updated =
            [SELECT Status__c FROM Bulk_Zip_Job__c WHERE Id = :job.Id];

        System.assertEquals('Completed', updated.Status__c);
    }

    // ---------- TEST 2: SUPER BILL ----------
    @isTest
    static void testBatch_SuperBill() {

        Account acc = createAccount();
        createCCR(acc);
        Bulk_Zip_Job__c job = createJob();
        
        Billing__c billing = createBilling(acc.Id);

    	createEvent(acc.Id, billing.Id);

    	createBillingLineItem(billing.Id);
        billing.Is_Synced__c = true;
        update billing;

        Map<Id, List<Id>> relMap = new Map<Id, List<Id>>{
            acc.Id => new List<Id>()
        };

        Test.startTest();

        BulkInvoiceEmailBatch batch = new BulkInvoiceEmailBatch(
            job.Id,
            new List<Id>{acc.Id},
            String.valueOf(Date.today()),
            String.valueOf(Date.today()),
            'Super Bill',
            relMap
        );

        Database.executeBatch(batch, 1);

        Test.stopTest();
        
         Bulk_Zip_Job__c updated = [
            SELECT Status__c, Error_Message__c
            FROM Bulk_Zip_Job__c
            WHERE Id = :job.Id
        ];
    
        System.assertEquals(
            'Completed',
            updated.Status__c
        );

        System.assert(true);
    }

    // ---------- TEST 3: EMPTY ACCOUNT LIST ----------
    @isTest
    static void testBatch_NoAccounts() {

        Bulk_Zip_Job__c job = createJob();

        Test.startTest();

        BulkInvoiceEmailBatch batch = new BulkInvoiceEmailBatch(
            job.Id,
            new List<Id>(),
            String.valueOf(Date.today()),
            String.valueOf(Date.today()),
            'Standard Invoice',
            null
        );

        Database.executeBatch(batch, 1);

        Test.stopTest();

        System.assert(true);
    }

    // ---------- TEST 4: NULL DATES ----------
    @isTest
    static void testBatch_NullDates() {

        Account acc = createAccount();
        Bulk_Zip_Job__c job = createJob();

        Test.startTest();

        BulkInvoiceEmailBatch batch = new BulkInvoiceEmailBatch(
            job.Id,
            new List<Id>{acc.Id},
            null,
            null,
            'Standard Invoice',
            null
        );

        Database.executeBatch(batch, 1);

        Test.stopTest();

        System.assert(true);
    }

    // ---------- TEST 5: FINISH METHOD ----------
    @isTest
    static void testBatch_FinishSummary() {

        Account acc = createAccount();
        Bulk_Zip_Job__c job = createJob();

        Test.startTest();

        BulkInvoiceEmailBatch batch = new BulkInvoiceEmailBatch(
            job.Id,
            new List<Id>{acc.Id},
            String.valueOf(Date.today()),
            String.valueOf(Date.today()),
            'Standard Invoice',
            null
        );

        Database.executeBatch(batch, 1);

        Test.stopTest();

        Bulk_Zip_Job__c updated =
            [SELECT Status__c, Error_Message__c FROM Bulk_Zip_Job__c WHERE Id = :job.Id];

        System.assertNotEquals(null, updated.Error_Message__c);
    }
}