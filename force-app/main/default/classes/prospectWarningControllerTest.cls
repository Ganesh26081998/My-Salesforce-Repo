@IsTest
private class prospectWarningControllerTest {

   

    private static Account createPersonAccount() {

        Id personRtId;

        Map<String, Schema.RecordTypeInfo> rtMap =
            Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName();

        if (rtMap.containsKey('PersonAccount')) {
            personRtId =
                rtMap.get('PersonAccount').getRecordTypeId();
        }

        Account pa;

        if (personRtId != null) {

            pa = new Account(
                RecordTypeId = personRtId,
                FirstName = 'John',
                LastName = 'Doe',
                PersonEmail = 'john@test.com',
                HowDidYouFindUs__c = 'Google'
            );

        } else {

            pa = new Account(
                Name = 'Test Person Account',
                HowDidYouFindUs__c = 'Google'
            );
        }

        insert pa;

        return pa;
    }


    @IsTest
    static void testGetProspectInfo() {

        Account pa = createPersonAccount();

        
        if (pa.PersonContactId != null) {

            
            List<RecordType> contactRTs = [
                SELECT Id, DeveloperName
                FROM RecordType
                WHERE SObjectType = 'Contact'
                LIMIT 1
            ];

            Contact relatedCon = new Contact(
                LastName = 'Related Contact',
                RecordTypeId = contactRTs[0].Id
            );

            insert relatedCon;

            
            HealthCloudGA__ContactContactRelation__c rel =
                new HealthCloudGA__ContactContactRelation__c(
                    HealthCloudGA__RelatedContact__c =
                        pa.PersonContactId,
                    HealthCloudGA__Contact__c =
                        relatedCon.Id
                );

            insert rel;
        }

        Test.startTest();

        prospectWarningController.ProspectInfo info =
            prospectWarningController.getProspectInfo(
                pa.Id
            );

        Test.stopTest();

        System.assertNotEquals(null, info);

        System.assertEquals(
            'Google',
            info.self
        );
    }


    @IsTest
    static void testGetProspectInfoNull() {

        Test.startTest();

        prospectWarningController.ProspectInfo info =
            prospectWarningController.getProspectInfo(null);

        Test.stopTest();

        System.assertEquals(null, info);
    }


    @IsTest
    static void testProspectInfoConstructor() {

        Test.startTest();

        prospectWarningController.ProspectInfo info =
            new prospectWarningController.ProspectInfo(
                true,
                false,
                'Website'
            );

        Test.stopTest();

        System.assertEquals(
            true,
            info.Businessflag
        );

        System.assertEquals(
            false,
            info.Individualflag
        );

        System.assertEquals(
            'Website',
            info.self
        );
    }
}