/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : QuickBooksInvoiceService
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : Builds QuickBooks Invoice payloads from Salesforce Billing data,
creates or updates the QuickBooks Invoice, and returns the
QuickBooks identifiers needed for Salesforce updates.
----------------------------------------------------------------------------
*/

public inherited sharing class QuickBooksInvoiceService {
    public static final String EXCLUDED_LINE_ITEM_TYPE = 'Caregiver Billable';
    
    private static final String DETAIL_TYPE_SALES_ITEM = 'SalesItemLineDetail';
    private static final String NON_TAXABLE_CODE = 'NON';
    private static final String INVOICE_ENDPOINT = '/invoice?minorversion=65';

    // Default line description fallback names
    private static final Map<String, String> DEFAULT_ITEM_NAMES = new Map<String, String>{
        'Client Billable' => 'Client Credits',
        'Mileage'         => 'Client Mileage',
        'Expense/Credit'  => 'Client Expenses'
    };
            
    public class InvoiceResult {
        public String invoiceId;
        public List<Billing_Line_Item__c> lineItemsToUpdate = new List<Billing_Line_Item__c>();
    }
    
    /**
     * Dynamically fetches location settings from Custom Metadata Type.
     * Supports looking up by City name (which references a Parent State) or State directly.
     */
    private static QuickBooks_Location_Setting__mdt getLocationSetting(String location) {
        if (String.isBlank(location)) {
            throw new QuickBooksException('Location is required for invoice sync.');
        }

        String searchKey = location.trim();
        QuickBooks_Location_Setting__mdt setting = QuickBooks_Location_Setting__mdt.getInstance(searchKey);
        
        // Case-insensitive scan fallback
        if (setting == null) {
            for (QuickBooks_Location_Setting__mdt mdt : QuickBooks_Location_Setting__mdt.getAll().values()) {
                if (mdt.MasterLabel.equalsIgnoreCase(searchKey)) {
                    setting = mdt;
                    break;
                }
            }
        }

        if (setting == null) {
            throw new QuickBooksException('No QuickBooks configuration found for location/state: ' + location);
        }

        // If this record is a City pointing to a State (via Named_Credential_Key__c) and has no item IDs of its own,
        // inherit the settings from the parent State metadata record.
        if (String.isBlank(setting.Client_Billable_Item_ID__c) && String.isNotBlank(setting.Named_Credential_Key__c)) {
            QuickBooks_Location_Setting__mdt parentSetting = QuickBooks_Location_Setting__mdt.getInstance(setting.Named_Credential_Key__c.trim());
            if (parentSetting != null) {
                return parentSetting;
            }
        }

        return setting;
    }

    public static String createInvoice(Billing__c billing, Account account, String location) {
        InvoiceResult result = createInvoiceResult(new List<Billing__c>{billing}, account, location, getLineItems(billing.Id));
        
        if (!result.lineItemsToUpdate.isEmpty()) {
            update result.lineItemsToUpdate;
        }
        return result.invoiceId;
    }
    
    public static InvoiceResult createInvoiceResult(
        List<Billing__c> billings,
        Account account,
        String location,
        List<Billing_Line_Item__c> lineItems
    ) {
        try {
            validateInvoiceInput(billings, account, location, lineItems);
            
            Map<String, Object> invoiceMap = buildInvoiceMap(billings, account, lineItems, location);
            String jsonBody = JSON.serialize(invoiceMap);
            String existingInvoiceId = null;
            
            for (Billing__c b : billings) {
                if (String.isNotBlank(b.QB_Invoice_Id__c)) {
                    existingInvoiceId = b.QB_Invoice_Id__c;
                    break;
                }
            }
            
            if (String.isNotBlank(existingInvoiceId)) {
                return updateInvoiceInQB(existingInvoiceId, invoiceMap, lineItems, location);
            }
            
            return createInvoiceInQB(jsonBody, lineItems, location);
        } catch (Exception e) {
            throw new QuickBooksException('Error creating invoice: ' + e.getMessage());
        }
    }
    
    private static void validateInvoiceInput(
        List<Billing__c> billings,
        Account account,
        String location,
        List<Billing_Line_Item__c> lineItems
    ) {
        if (billings == null || billings.isEmpty()) {
            throw new QuickBooksException('No billing records provided to sync.');
        }
        if (String.isBlank(location)) {
            throw new QuickBooksException('Location is required for invoice sync');
        }
        if (account == null || String.isBlank(account.QB_Customer_Id__c)) {
            throw new QuickBooksException('Account does not have QB Customer ID. Please sync the Customer first.');
        }
        if (lineItems == null || lineItems.isEmpty()) {
            throw new QuickBooksException('Sync Failed: No valid line items found (Caregiver Billables are excluded).');
        }
    }
    
    private static List<Billing_Line_Item__c> getLineItems(Id billingId) {
        return [
            SELECT Id, Description__c, Quantity__c, Rate__c, Amount__c, Type__c
            FROM Billing_Line_Item__c
            WHERE Invoice__c = :billingId
            AND Type__c != :EXCLUDED_LINE_ITEM_TYPE
            ORDER BY CreatedDate ASC
        ];
    }
    
    private static Map<String, Object> buildInvoiceMap(
        List<Billing__c> billings,
        Account account,
        List<Billing_Line_Item__c> lineItems,
        String location
    ) {
        Map<String, Object> invoiceMap = new Map<String, Object>();
        Billing__c primaryBilling = billings[0]; 
        
        Date transactionDate = primaryBilling.Invoice_Date__c == null ? Date.today() : primaryBilling.Invoice_Date__c;
        invoiceMap.put('TxnDate', String.valueOf(transactionDate));
        
        if (primaryBilling.Due_Date__c != null) {
            invoiceMap.put('DueDate', String.valueOf(primaryBilling.Due_Date__c));
        }
        
        invoiceMap.put('CustomerRef', new Map<String, Object>{ 'value' => account.QB_Customer_Id__c });
        
        if (String.isNotBlank(account.PersonEmail)) {
            invoiceMap.put('BillEmail', new Map<String, Object>{ 'Address' => account.PersonEmail });
        }
        
        if (String.isNotBlank(primaryBilling.Location_g__c)) {
            invoiceMap.put('ShipAddr', new Map<String, Object>{ 'Line1' => primaryBilling.Location_g__c });
        }
        
        List<String> combinedNotes = new List<String>();
        for (Billing__c b : billings) {
            if (String.isNotBlank(b.Notes__c)) {
                combinedNotes.add(b.Notes__c);
            }
        }
        
        if (!combinedNotes.isEmpty()) {
            invoiceMap.put('CustomerMemo', new Map<String, Object>{ 'value' => String.join(combinedNotes, ' | ').abbreviate(4000) });
        }
        
        invoiceMap.put('Line', buildInvoiceLines(lineItems, location));
        return invoiceMap;
    }
    
    private static List<Map<String, Object>> buildInvoiceLines(List<Billing_Line_Item__c> lineItems, String location) {
        List<Map<String, Object>> lines = new List<Map<String, Object>>();
        Integer lineNumber = 1;
        
        // Dynamically fetch item IDs from Custom Metadata
        QuickBooks_Location_Setting__mdt setting = getLocationSetting(location);
        
        for (Billing_Line_Item__c lineItem : lineItems) {
            Decimal quantity = lineItem.Quantity__c == null ? 1 : lineItem.Quantity__c;
            Decimal rate = lineItem.Rate__c == null ? 0 : lineItem.Rate__c;
            
            String qbItemId = getItemIdForType(setting, lineItem.Type__c);
            
            if (String.isBlank(qbItemId)) {
                throw new QuickBooksException(
                    'No QB Item configured for Type: ' + lineItem.Type__c + ' at Location: ' + location
                );
            }
            
            String itemName = DEFAULT_ITEM_NAMES.containsKey(lineItem.Type__c) 
                ? DEFAULT_ITEM_NAMES.get(lineItem.Type__c) 
                : lineItem.Type__c;
            
            Map<String, Object> lineMap = new Map<String, Object>{
                'LineNum' => lineNumber,
                'DetailType' => DETAIL_TYPE_SALES_ITEM,
                'Description' => String.isNotBlank(lineItem.Description__c) ? lineItem.Description__c : itemName,
                'Amount' => quantity * rate,
                'SalesItemLineDetail' => new Map<String, Object>{
                    'Qty' => quantity,
                    'UnitPrice' => rate,
                    'ItemRef' => new Map<String, Object>{ 
                        'value' => qbItemId, 
                        'name'  => itemName 
                    },
                    'TaxCodeRef' => new Map<String, Object>{ 'value' => NON_TAXABLE_CODE }
                }
            };
                
            lines.add(lineMap);
            lineNumber++;
        }
        
        return lines;
    }

    private static String getItemIdForType(QuickBooks_Location_Setting__mdt setting, String itemType) {
        if (itemType == 'Client Billable') {
            return setting.Client_Billable_Item_ID__c;
        } else if (itemType == 'Mileage') {
            return setting.Mileage_Item_ID__c;
        } else if (itemType == 'Expense/Credit') {
            return setting.Expense_Credit_Item_ID__c;
        }
        return null;
    }
    
    private static InvoiceResult createInvoiceInQB(
        String jsonBody,
        List<Billing_Line_Item__c> salesforceLines,
        String location
    ) {
        HttpResponse response = QuickBooksAuthService.makeApiCall(INVOICE_ENDPOINT, 'POST', jsonBody, location);
        
        if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
            return processResponse(response.getBody(), salesforceLines);
        }
        
        throw new QuickBooksException('QB Invoice Creation Failed: ' + response.getStatus() + ' - ' + response.getBody());
    }
    
    private static InvoiceResult updateInvoiceInQB(
        String invoiceId,
        Map<String, Object> invoiceMap,
        List<Billing_Line_Item__c> salesforceLines,
        String location
    ) {
        invoiceMap.put('Id', invoiceId);
        invoiceMap.put('SyncToken', getSyncToken(invoiceId, location));
        invoiceMap.put('sparse', true);
        
        HttpResponse response = QuickBooksAuthService.makeApiCall(INVOICE_ENDPOINT, 'POST', JSON.serialize(invoiceMap), location);
        
        if (response.getStatusCode() == 200) {
            return processResponse(response.getBody(), salesforceLines);
        }
        
        throw new QuickBooksException('QB Invoice Update Failed: ' + response.getStatus() + ' - ' + response.getBody());
    }
    
    private static String getSyncToken(String invoiceId, String location) {
        HttpResponse response = QuickBooksAuthService.makeApiCall('/invoice/' + invoiceId + '?minorversion=65', 'GET', null, location);
        
        if (response.getStatusCode() != 200) {
            return '0';
        }
        
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        Map<String, Object> invoice = (Map<String, Object>) responseMap.get('Invoice');
        return invoice == null ? '0' : (String) invoice.get('SyncToken');
    }
    
    private static InvoiceResult processResponse(String responseBody, List<Billing_Line_Item__c> salesforceLines) {
        InvoiceResult result = new InvoiceResult();
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> invoice = (Map<String, Object>) responseMap.get('Invoice');
        
        if (invoice == null) {
            return result;
        }
        
        result.invoiceId = (String) invoice.get('Id');
        result.lineItemsToUpdate.addAll(buildLineItemUpdates(invoice, salesforceLines));
        return result;
    }
    
    private static List<Billing_Line_Item__c> buildLineItemUpdates(
        Map<String, Object> invoice,
        List<Billing_Line_Item__c> salesforceLines
    ) {
        List<Billing_Line_Item__c> linesToUpdate = new List<Billing_Line_Item__c>();
        
        if (salesforceLines == null || salesforceLines.isEmpty() || !invoice.containsKey('Line')) {
            return linesToUpdate;
        }
        
        List<Object> returnedLines = (List<Object>) invoice.get('Line');
        for (Integer index = 0; index < salesforceLines.size() && index < returnedLines.size(); index++) {
            Map<String, Object> returnedLine = (Map<String, Object>) returnedLines[index];
            if (returnedLine.get('DetailType') == DETAIL_TYPE_SALES_ITEM) {
                linesToUpdate.add(new Billing_Line_Item__c(
                    Id = salesforceLines[index].Id,
                    QB_Line_Item_ID__c = (String) returnedLine.get('Id')
                ));
            }
        }
        
        return linesToUpdate;
    }
}