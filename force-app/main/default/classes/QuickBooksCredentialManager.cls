/*
----------------------------------------------------------------------------
Author        : Rohit Dhote
Class Name    : QuickBooksCredentialManager
CreatedOn     : 13-12-2025
LastModifiedOn: 18-05-2026
LastModifiedBy: Rohit Dhote
Description   : Resolves the Named Credential endpoint used to route each
                Billing sync to the correct QuickBooks location.
----------------------------------------------------------------------------
*/

public inherited sharing class QuickBooksCredentialManager {
    private static final String NAMED_CREDENTIAL_PREFIX = 'QuickBooksSalesforce_';
    private static final String CALLOUT_PREFIX = 'callout:';

    public static String getCredentialNameForLocation(String location) {
        if (String.isBlank(location)) {
            throw new IllegalArgumentException('Location cannot be empty.');
        }

        return NAMED_CREDENTIAL_PREFIX + location.trim();
    }

    public static String getNamedCredentialURL(String location) {
        try {
            return CALLOUT_PREFIX + getCredentialNameForLocation(location);
        } catch (Exception e) {
            throw new QuickBooksException('QB credential not configured for location: ' + location);
        }
    }

    public static Boolean isLocationCredentialConfigured(String location) {
        try {
            getNamedCredentialURL(location);
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}