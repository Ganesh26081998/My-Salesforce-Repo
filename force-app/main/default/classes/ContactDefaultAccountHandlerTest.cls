@IsTest
private class ContactDefaultAccountHandlerTest {

    @testSetup
    static void setupData() {

        Account acc = new Account(Name = 'No Organization');
        insert acc;
    }

    @IsTest
    static void testAssignDefaultAccount() {

        Contact c1 = new Contact(LastName = 'Testa');
        Contact c2 = new Contact(LastName = 'Testb');

        List<Contact> conList = new List<Contact>{ c1, c2 };

        Test.startTest();
        ContactDefaultAccountHandler.beforeInsert(conList);
        insert conList;
        Test.stopTest();

        for (Contact c : conList) {
            System.assertNotEquals(null, c.AccountId);
        }
    }

    @IsTest
    static void testNoDefaultNeeded() {

        Account acc = [SELECT Id FROM Account WHERE Name = 'No Organization' LIMIT 1];

        Contact c = new Contact(
            LastName = 'AlreadyAssigned',
            AccountId = acc.Id
        );

        List<Contact> conList = new List<Contact>{ c };

        Test.startTest();
        ContactDefaultAccountHandler.beforeInsert(conList);
        insert conList;
        Test.stopTest();

        System.assertEquals(acc.Id, c.AccountId);
    }

    @IsTest
    static void testNullList() {

        Test.startTest();
        ContactDefaultAccountHandler.beforeInsert(null);
        Test.stopTest();

        System.assert(true);
    }
}