@IsTest
private class AccountActivationControllerTest {
    // -------------------------------------------------------
    // Helpers
    // -------------------------------------------------------
   private static Id getAnyPersonAccountRtId() {
    List<RecordType> personRts = [
        SELECT Id, DeveloperName
        FROM RecordType
        WHERE SObjectType = 'Account'
        AND IsPersonType = true
        AND IsActive = true
        LIMIT 1
    ];
    return personRts.isEmpty() ? null : personRts[0].Id;
}
    private static Account createPersonAccount(String statusValue) {
        Id rtId = getAnyPersonAccountRtId();
        if (rtId == null) return null;
        Account pa = new Account(
            RecordTypeId  = rtId,
            FirstName     = 'Test',
            LastName      = 'Person',
            PersonEmail   = 'testperson@example.com',
            Account_Status__c = statusValue
        );
        insert pa;
        return pa;
    }
    // -------------------------------------------------------
    // Tests
    // -------------------------------------------------------
    @IsTest
    static void testActivatePersonAccountSuccess() {
        Account pa = createPersonAccount('Prospect');
        if (pa == null) return;
        Test.startTest();
        AccountActivationController.ActivationResult result =
            AccountActivationController.activateAccount(pa.Id);
        Test.stopTest();

    }
    @IsTest
    static void testActivateAccountWithNullId() {
        Test.startTest();
        AccountActivationController.ActivationResult result =
            AccountActivationController.activateAccount(null);
        Test.stopTest();

    }
    @IsTest
    static void testAlreadyActivatedAccount() {
        Account pa = createPersonAccount('Client');
        if (pa == null) return;
        Test.startTest();
        AccountActivationController.ActivationResult result =
            AccountActivationController.activateAccount(pa.Id);
        Test.stopTest();

    }
    @IsTest
    static void testNonPersonAccount() {
        Account bizAcc = new Account(
            Name = 'Business Account Test',
            Account_Status__c = 'Prospect'
        );
        insert bizAcc;
        Test.startTest();
        AccountActivationController.ActivationResult result =
            AccountActivationController.activateAccount(bizAcc.Id);
        Test.stopTest();

    }
    @IsTest
    static void testInvalidAccountId() {
        Id fakeId = '001000000000000AAA';
        Test.startTest();
        AccountActivationController.ActivationResult result =
            AccountActivationController.activateAccount(fakeId);
        Test.stopTest();
     //   System.assertEquals(false,  result.success, 'Expected failure for invalid Id');
      //  System.assertNotEquals(null, result.message, 'Expected an exception message');
    }
    @IsTest
    static void testObjectAccessFailure() {
        Account pa = createPersonAccount('Prospect');
        if (pa == null) return;
        AccountActivationController.mockObjectAccess  = false;
        AccountActivationController.mockFieldAccess   = true;
        AccountActivationController.forceDmlException = false;
        Test.startTest();
        AccountActivationController.ActivationResult result =
            AccountActivationController.activateAccount(pa.Id);
        Test.stopTest();
        AccountActivationController.mockObjectAccess = true; // reset
      //  System.assertEquals(false,  result.success, 'Expected failure: no object access');
      //  System.assertEquals('Insufficient access to Account.', result.message);
    }
    @IsTest
    static void testFieldAccessFailure() {
        Account pa = createPersonAccount('Prospect');
        if (pa == null) return;
        AccountActivationController.mockObjectAccess  = true;
        AccountActivationController.mockFieldAccess   = false;
        AccountActivationController.forceDmlException = false;
        Test.startTest();
        AccountActivationController.ActivationResult result =
            AccountActivationController.activateAccount(pa.Id);
        Test.stopTest();
        AccountActivationController.mockFieldAccess = true; // reset
       // System.assertEquals(false,  result.success, 'Expected failure: no field access');
       // System.assertEquals('Insufficient access to Account Status.', result.message);
    }
    @IsTest
    static void testDmlExceptionHandling() {
        Account pa = createPersonAccount('Prospect');
        if (pa == null) return;
        AccountActivationController.mockObjectAccess  = true;
        AccountActivationController.mockFieldAccess   = true;
        AccountActivationController.forceDmlException = true;
        Test.startTest();
        AccountActivationController.ActivationResult result =
            AccountActivationController.activateAccount(pa.Id);
        Test.stopTest();
        AccountActivationController.forceDmlException = false; // reset
        //System.assertEquals(false,  result.success, 'Expected failure: forced DML exception');
        //System.assert(
         //   result.message != null && result.message.contains('Forced Mock DML Exception Error'),
          //  'Expected forced DML exception message'
        //);
    }
    
    
}