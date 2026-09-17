/*public with sharing class BillableListViewController {

    @AuraEnabled(cacheable=true)
    public static List<Billing__c> getBillables() {
        return [
            SELECT Id,
                   Name,
                   Client__c,
                   Client__r.Name,
                   Is_Synced__c,
                   Amount__c,
                   QB_Sync_Status__c,
                   Owner.Name,
                   Location_g__c ,
                   CreatedDate,
                   LastModifiedDate,
                   Event_Start_Date_Time__c,
                   Event_End_Date_Time__c
            FROM Billing__c
            where QB_Sync_Status__c!= 'Synced' 
            AND Client__r.RecordType.Name = 'Prospect' 
            AND QB_Sync_Status__c!= 'Failed' 
            AND (Client__r.Name!= 'WellSpring Office Hours%')
            
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];
    }
}*/
public with sharing class BillableListViewController {

    @AuraEnabled(cacheable=true)
    public static List<Billing__c> getBillables() {

        // Fetch records from Salesforce
        List<Billing__c> billings = [
            SELECT Id,
                   Name,
                   Client__c,
                   Client__r.Name,
                   Is_Synced__c,
                   Amount__c,
                   QB_Sync_Status__c,
                   Owner.Name,
                   Location_g__c,
                   CreatedDate,
                   LastModifiedDate,
                   Event_Start_Date_Time__c,
                   Event_End_Date_Time__c
            FROM Billing__c
            WHERE QB_Sync_Status__c != 'Synced'
              AND QB_Sync_Status__c != 'Failed'
              AND Client__r.RecordType.Name = 'Prospect'
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];

        // Remove Office Hours records
       /* List<Billing__c> filteredBillings = new List<Billing__c>();

        for (Billing__c bill : billings) {

            if (bill.Client__r == null ||
                bill.Client__r.Name == null ||
                !bill.Client__r.Name.startsWith('WellSpring Office Hours')) {

                filteredBillings.add(bill);
            }
        }

        return filteredBillings; */
        // Filter Office Hours and group by Client
Map<Id, List<Billing__c>> groupedBillings = new Map<Id, List<Billing__c>>();
List<Id> clientOrder = new List<Id>();

for (Billing__c bill : billings) {

    // Skip Office Hours clients
    if (bill.Client__r != null &&
        bill.Client__r.Name != null &&
        bill.Client__r.Name.startsWith('WellSpring Office Hours')) {
        continue;
    }

    // Maintain client order based on latest billable
    if (!groupedBillings.containsKey(bill.Client__c)) {
        groupedBillings.put(bill.Client__c, new List<Billing__c>());
        clientOrder.add(bill.Client__c);
    }

    groupedBillings.get(bill.Client__c).add(bill);
}

// Prepare final list
List<Billing__c> finalList = new List<Billing__c>();

for (Id clientId : clientOrder) {
    finalList.addAll(groupedBillings.get(clientId));
}

return finalList;
    }
}