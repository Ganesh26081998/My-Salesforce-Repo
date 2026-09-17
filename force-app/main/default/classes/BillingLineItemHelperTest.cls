@isTest
public class BillingLineItemHelperTest {
    
    @isTest
    static void testCreateLineItems_AllScenarios() {
        
        // ---------- Create Event ----------
        Event ev = new Event(
            Subject = 'Test Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),
            
            // Client
            Client_Rate_Amount__c = 100,
            Client_Billing_Details__c = 'Client Details',
            Client_Rate__c = 'Hourly',
            
            // Caregiver
            Caregiver_Rate_Amount__c = 80,
            Caregiver_Billing_Details__c = 'Caregiver Details',
            Caregiver_Rate__c = 'Hourly',
            
            // Mileage (multiple)
            Mileage_Amount__c = 10,
            Mileage_Description__c = 'Mileage 1',
            
            Mileage_Amount_2__c = 20,
            Mileage_Description_2__c = 'Mileage 2',
            
            // Expense (multiple)
            Expense_Amount__c = 15,
            Expense_Description__c = 'Expense 1',
            
            Expense_Amount_2__c = 25,
            Expense_Description_2__c = 'Expense 2'
        );
        
        insert ev;
        
        Account acc = New Account(Name = 'Test user');
        
        insert acc;
        
        // ---------- Create Billing ----------
        Billing__c bill = new Billing__c(
            Amount__c = 200,
            Care_From_Date__c = Date.newInstance(2026, 2, 16),
            Care_To_Date__c = Date.newInstance(2026, 2, 16),
            Client__c = acc.Id,
            
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = Date.newInstance(2026, 2, 1),
            Invoice_Period_End_Date__c = Date.newInstance(2026, 2, 28),
            
            Paid_Status__c = 'Paid' // ⚠️ must match your picklist values
        );
        
        insert bill;
        
        
        // ---------- Prepare Maps ----------
        Map<Id, Billing__c> eventToBillingMap = new Map<Id, Billing__c>{
            ev.Id => bill
                };
                    
                    Map<Id, Event> eventMap = new Map<Id, Event>{
                        ev.Id => ev
                            };
                                
                                // ---------- Call Method ----------
                                List<Billing_Line_Item__c> items =
                                BillingLineItemHelper.createLineItems(eventToBillingMap, eventMap);
        
        // ---------- Assertions ----------
        
        System.assertNotEquals(null, items);
        System.assert(items.size() > 0, 'Items should be created');
        
        // Expected:
        // 1 Client + 1 Caregiver + 2 Mileage + 2 Expense = 6
        System.assertEquals(6, items.size(), 'Total line items mismatch');
        
        // Validate Types exist
        Set<String> types = new Set<String>();
        for (Billing_Line_Item__c item : items) {
            types.add(item.Type__c);
        }
        
        System.assert(types.contains('Mileage'));
        System.assert(types.contains('Expense/Credit'));
    }
    
    // ---------- Test: No values (edge case) ----------
    @isTest
    static void testCreateLineItems_NoValues() {
        
        Event ev = new Event(
            Subject = 'Empty Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1)
        );
        insert ev;
        
        Account acc = New Account(Name = 'Test user');
        
        insert acc;
        
        // ---------- Create Billing ----------
        Billing__c bill = new Billing__c(
            Amount__c = 200,
            Care_From_Date__c = Date.newInstance(2026, 2, 16),
            Care_To_Date__c = Date.newInstance(2026, 2, 16),
            Client__c = acc.Id,
            
            Invoice_Date__c = Date.today(),
            Invoice_Period_Start_Date__c = Date.newInstance(2026, 2, 1),
            Invoice_Period_End_Date__c = Date.newInstance(2026, 2, 28),
            
            Paid_Status__c = 'Paid' // ⚠️ must match your picklist values
        );
        
        insert bill;
        
        Map<Id, Billing__c> eventToBillingMap = new Map<Id, Billing__c>{
            ev.Id => bill
                };
                    
                    Map<Id, Event> eventMap = new Map<Id, Event>{
                        ev.Id => ev
                            };
                                
                                List<Billing_Line_Item__c> items =
                                BillingLineItemHelper.createLineItems(eventToBillingMap, eventMap);
        
        System.assertEquals(0, items.size(), 'No items should be created');
    }
}