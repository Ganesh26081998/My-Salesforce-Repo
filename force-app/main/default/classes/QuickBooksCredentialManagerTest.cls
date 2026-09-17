@IsTest
private class QuickBooksCredentialManagerTest {

    @IsTest
    static void testGetCredentialNameForLocation_Valid() {
        String result = QuickBooksCredentialManager.getCredentialNameForLocation('Detroit');

        System.assertEquals(
            'QuickBooksSalesforce_Detroit',
            result
        );
    }

    @IsTest
    static void testGetCredentialNameForLocation_WithSpaces() {
        String result = QuickBooksCredentialManager.getCredentialNameForLocation('  Milwaukee  ');

        System.assertEquals(
            'QuickBooksSalesforce_Milwaukee',
            result
        );
    }

    @IsTest
    static void testGetCredentialNameForLocation_Empty_ShouldThrow() {
        try {
            QuickBooksCredentialManager.getCredentialNameForLocation('');
            System.assert(false, 'Expected exception not thrown');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Location cannot be empty'));
        }
    }

    @IsTest
    static void testGetCredentialNameForLocation_Null_ShouldThrow() {
        try {
            QuickBooksCredentialManager.getCredentialNameForLocation(null);
            System.assert(false, 'Expected exception not thrown');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Location cannot be empty'));
        }
    }

    @IsTest
    static void testGetNamedCredentialURL_Valid() {
        String url = QuickBooksCredentialManager.getNamedCredentialURL('Cincinnati');

        System.assertEquals(
            'callout:QuickBooksSalesforce_Cincinnati',
            url
        );
    }

    @IsTest
    static void testGetNamedCredentialURL_Empty_ShouldThrowWrappedException() {
        try {
            QuickBooksCredentialManager.getNamedCredentialURL('');
            System.assert(false, 'Expected exception not thrown');
        } catch (QuickBooksException e) {
            System.assert(
                e.getMessage().contains('QB credential not configured')
            );
        }
    }

    @IsTest
    static void testGetNamedCredentialURL_Null_ShouldThrowWrappedException() {
        try {
            QuickBooksCredentialManager.getNamedCredentialURL(null);
            System.assert(false, 'Expected exception not thrown');
        } catch (QuickBooksException e) {
            System.assert(
                e.getMessage().contains('QB credential not configured')
            );
        }
    }

    @IsTest
    static void testIsLocationCredentialConfigured_True() {
        Boolean result = QuickBooksCredentialManager.isLocationCredentialConfigured('Detroit');

        System.assertEquals(true, result);
    }

    @IsTest
    static void testIsLocationCredentialConfigured_False() {
        // Force failure path by passing invalid input
        Boolean result = QuickBooksCredentialManager.isLocationCredentialConfigured('');

        System.assertEquals(false, result);
    }

    @IsTest
    static void testIsLocationCredentialConfigured_Null() {
        Boolean result = QuickBooksCredentialManager.isLocationCredentialConfigured(null);

        System.assertEquals(false, result);
    }
}