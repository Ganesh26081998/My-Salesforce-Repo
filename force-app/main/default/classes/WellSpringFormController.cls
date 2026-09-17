/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : WellSpringFormController
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : This Apex class validates web form submissions, prevents duplicate emails, 
                manages dynamic UI picklist options, and creates new Person Account prospects in Salesforce.
----------------------------------------------------------------------------
*/

public without sharing class WellSpringFormController {

    /**
     * @description: Create Person Account from web form submission
     * @param firstName - Account first name
     * @param lastName - Account last name
     * @param email - Account email (PersonEmail)
     * @param phone - Account phone (Mobile_Phones__c)
     * @param street - Account street (Address_Prospect__c)
     * @param city - Account city (City_Prospect__c)
     * @param state - Account state (State_Pr__c)
     * @param zip - Account postal code (Postal_Code_Pr__c)
     * @param iAm - I am field value
     * @param otherIAm - "Other" details for I am field
     * @param otherRelationship - Your Relationship field value
     * @param heardAboutUs - How did you hear about us field value
     * @param otherHeardAboutUs - "Other" details for heard about us field
     * @param message - Message from user (Message__c)
     * @return: String - Account Id of created record
     */
    @AuraEnabled
    public static String createAccount(
        String firstName,
        String lastName,
        String email,
        String phone,
        String street,
        String city,
        String state,
        String zip,
        String iAm,
        String otherIAm,
        String otherRelationship,
        String heardAboutUs,
        String otherHeardAboutUs,
        String message
    ) {
        
        // 1. Validations moved outside the try block
        if (String.isBlank(firstName) || String.isBlank(lastName) || String.isBlank(email)) {
            AuraHandledException e = new AuraHandledException('First name, last name, and email are required');
            e.setMessage('First name, last name, and email are required');
            throw e;
        }
        
        if (!isValidEmail(email)) {
            AuraHandledException e = new AuraHandledException('Please enter a valid email address');
            e.setMessage('Please enter a valid email address');
            throw e;
        }
        
        List<Account> existingAccounts = [
            SELECT Id
            FROM Account
            WHERE PersonEmail = :email
            LIMIT 1
        ];
        
        System.debug('Checking for duplicates. Existing accounts: ' + existingAccounts);

        if (!existingAccounts.isEmpty()) {
            AuraHandledException e = new AuraHandledException('Duplicate entry detected. An existing record already uses this email address');
            e.setMessage('Duplicate entry detected. An existing record already uses this email address');
            throw e;
        }

        // 2. DML Operations inside the try block
        try {
            Id recordTypeId = System.Label.Prospect_RT_DeveloperName;
            
            // Build message with "Other" details if specified
            String finalMessage = message;
            if (String.isNotBlank(otherIAm) && iAm == 'Other') {
                finalMessage = (String.isNotBlank(message) ? message + '\n' : '') + 
                               'I am (Other): ' + otherIAm;
            }
            if (String.isNotBlank(otherHeardAboutUs) && heardAboutUs == 'Other') {
                finalMessage = (String.isNotBlank(finalMessage) ? finalMessage + '\n' : '') + 
                               'How heard about us (Other): ' + otherHeardAboutUs;
            }
            
            // Create Person Account with custom field mappings
            Account acc = new Account();
            acc.RecordTypeId = recordTypeId;
            acc.FirstName = firstName;
            acc.LastName = lastName;
            acc.PersonEmail = email;
            acc.Mobile_Phones__c = phone;
            acc.Address_Prospect__c = street;
            acc.City_Prospect__c = city;
            acc.State_Pr__c = state;
            acc.Postal_Code_Pr__c = zip;
            acc.I_am__c = iAm;
            acc.Your_Relationship__c = iAm == 'Other' ? null : otherRelationship;
            acc.How_did_you_hear_about_us__c = heardAboutUs;
            acc.Message__c = finalMessage;
            acc.Account_Status__c = 'New Inquiry';
            acc.Prospect_Source__c = 'Website';

            insert acc;
            
            System.debug('Account created successfully with ID: ' + acc.Id);

            return acc.Id;
            
        } catch (DmlException e) {
            System.debug('DML Error: ' + e.getMessage());
            AuraHandledException ae = new AuraHandledException('Error creating record: ' + e.getMessage());
            ae.setMessage('Error creating record: ' + e.getMessage());
            throw ae;
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            AuraHandledException ae = new AuraHandledException('An error occurred: ' + e.getMessage());
            ae.setMessage('An error occurred: ' + e.getMessage());
            throw ae;
        }
    }
    
    /**
     * @description: Validate email format
     * @param email - Email address to validate
     * @return: Boolean - True if valid email format
     */
    private static Boolean isValidEmail(String email) {
        String emailRegex = '^[a-zA-Z0-9._|\\-]+@[a-zA-Z0-9._|\\-]+\\.[a-zA-Z]{2,}$';
        Pattern pattern = Pattern.compile(emailRegex);
        Matcher matcher = pattern.matcher(email);
        return matcher.matches();
    }
    
    /**
     * @description: Get picklist mapping configuration
     * Maps "I am" values to allowed "Your Relationship" values
     * @return: Map of I_am values to list of allowed Relationship values
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getRelationshipMapping() {
        Map<String, List<String>> relationshipMapping = new Map<String, List<String>>();
        
        // Updated to match actual Salesforce picklist values from Your_Relationship__c field
        relationshipMapping.put('Senior or Family Member', new List<String>{
            'Mother', 'Father', 'Son', 'Daughter', 'Sister', 'Sibling', 'Brother', 
            'Grandson', 'Granddaughter', 'Grandmother', 'Grandfather', 
            'Aunt', 'Uncle', 'Niece', 'Nephew', 'Cousin', 'Self', 
            'Other relative', 'Friend/Neighbor', 'Daughter-in-Law', 'Son-in-Law'
        });
        
        relationshipMapping.put('Healthcare Partner', new List<String>{
            'Mother', 'Father', 'Son', 'Daughter', 'Sister', 'Sibling', 'Brother', 
            'Grandson', 'Granddaughter', 'Grandmother', 'Grandfather', 
            'Aunt', 'Uncle', 'Niece', 'Nephew', 'Cousin', 'Self', 
            'Other relative', 'Friend/Neighbor', 'Daughter-in-Law', 'Son-in-Law',
            'Caregiver', 'Social Worker/Case Manager'
        });
        
        return relationshipMapping;
    }
}