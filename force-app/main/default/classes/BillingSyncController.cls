/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : BillingSyncController
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : It acts as the bridge between your Salesforce screen and the backend code,
                allowing a user to click a "Sync to QuickBooks" button on a specific record to instantly trigger the integration.
----------------------------------------------------------------------------
*/

public class BillingSyncController {
    
    @AuraEnabled
    public static String syncBillingToQB(Id billingId) {
        try {
            Billing__c billing = [
                SELECT Id, Name, Client__c, Invoice_Date__c, Due_Date__c, Amount__c, 
                       QB_Sync_Status__c, Location_g__c, Notes__c, QB_Invoice_Id__c,
                       Is_Synced__c
                FROM Billing__c
                WHERE Id = :billingId
                LIMIT 1
            ];
            
            if (billing == null) return 'Error: Billing record not found';
            
            //  NEW: Duplicate sync prevention - Check if already synced 
            if (billing.Is_Synced__c == true) {
                return 'Already Synced: This billing record is already synced with QuickBooks.';
            }
            //  -------------------------------- 
            
            if (String.isEmpty(billing.Location_g__c)) {
                billing.QB_Sync_Status__c = 'Failed';
                billing.QB_Sync_Error__c = 'Location field is required';
                update billing;
                return 'Error: Location field is required';
            }
            
            System.debug('Syncing: ' + billing.Name + ' | Location: ' + billing.Location_g__c);
            
            if (!QuickBooksCredentialManager.isLocationCredentialConfigured(billing.Location_g__c)) {
                billing.QB_Sync_Status__c = 'Failed';
                billing.QB_Sync_Error__c = 'No QB credential for location: ' + billing.Location_g__c;
                update billing;
                return 'Error: No QB credential configured for location: ' + billing.Location_g__c;
            }
            
           Account acc = [
                SELECT Id, Name, QB_Customer_Id__c, PersonEmail, Mobile_Phones__c, 
                       Address__Street__s, Address__City__s, Address__StateCode__s, 
                       Address__PostalCode__s, Address__CountryCode__s
                FROM Account
                WHERE Id = :billing.Client__c
                LIMIT 1
            ];
            
            // Sync Customer
            String qbCustomerId = QuickBooksCustomerService.createOrUpdateCustomer(acc, billing.Location_g__c);
            
            // Set in memory (don't update DB yet - no uncommitted work before API call)
            acc.QB_Customer_Id__c = qbCustomerId;
            
            // Sync Invoice (with updated Account in memory)
            String qbInvoiceId = QuickBooksInvoiceService.createInvoice(billing, acc, billing.Location_g__c);
            
            // Update Billing
            update new Billing__c(
                Id = billing.Id,
                QB_Invoice_Id__c = qbInvoiceId,
                QB_Sync_Status__c = 'Synced',
                QB_Sync_Error__c = null,
                Is_Synced__c = true,
                Synced_Date__c = System.now()
            );
            
            // NOW update Account (after all API calls are done)
            update new Account(Id = acc.Id, QB_Customer_Id__c = qbCustomerId);
            
            return 'Success! Synced to QB (' + billing.Location_g__c + '). Invoice ID: ' + qbInvoiceId;
            
        } catch (Exception e) {
            try {
                update new Billing__c(Id = billingId, QB_Sync_Status__c = 'Failed', QB_Sync_Error__c = e.getMessage());
            } catch (Exception ex) {
                System.debug('Update failed: ' + ex.getMessage());
            }
            return 'Error: ' + e.getMessage();
        }
    }
}