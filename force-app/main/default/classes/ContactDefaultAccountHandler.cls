/*
----------------------------------------------------------------------------
Author        : Bhanu Prakash
Class Name    : ContactDefaultAccountHandler
CreatedOn     : 18-02-2026
LastModifiedOn: 02-05-2026
LastModifiedBy: Bhanu Prakash
Description   : This class is used to automatically assign the default “No Organization” Account to Contacts when no Account is specified during record creation.



----------------------------------------------------------------------------
*/


public class ContactDefaultAccountHandler {
    
    public static void beforeInsert(List<Contact> newContacts) {

        if (newContacts == null || newContacts.isEmpty()) {
            return;
        }

        //  Check if ANY contact needs default account
        Boolean needsDefault = false;

        for (Contact con : newContacts) {
            if (con.AccountId == null) {
                needsDefault = true;
                break;
            }
        }

        if (!needsDefault) {
            return;
        }

        // Query default account ONLY ONCE
        Account defaultAccount = [
            SELECT Id
            FROM Account
            WHERE Name = :System.Label.Default_Organization_Account
            LIMIT 1
        ];

        if (defaultAccount == null) {
            return;
        }

        //  Assign to contacts missing AccountId
        for (Contact con : newContacts) {
            if (con.AccountId == null) {
                con.AccountId = defaultAccount.Id;
            }
        }
    }

}