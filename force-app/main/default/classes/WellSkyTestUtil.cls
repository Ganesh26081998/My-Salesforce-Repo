/**
 * Shared helpers for Apex tests — org-agnostic picklist values and trigger control.
 */
@IsTest
public class WellSkyTestUtil {

    private static final String DEPLOY_USER_USERNAME =
        'veerabhavani.polina@cloudodyssey.co.wellspring';

    private static Boolean healthCloudPermEnsured = false;
    private static User testHealthCloudUser;

    public static void initializeDeployTestUser() {
        if (!Test.isRunningTest()) {
            return;
        }
        getAdminUser();
    }

    public static User getAdminUser() {
        if (Test.isRunningTest()) {
            if (testHealthCloudUser != null) {
                return testHealthCloudUser;
            }
            List<User> hcAdmins = [
                SELECT Id
                FROM User
                WHERE IsActive = true
                AND Id IN (
                    SELECT AssigneeId
                    FROM PermissionSetAssignment
                    WHERE PermissionSet.Name = 'HealthCloudAdmin'
                )
                LIMIT 1
            ];
            if (!hcAdmins.isEmpty()) {
                testHealthCloudUser = hcAdmins[0];
                return testHealthCloudUser;
            }
            List<User> deployUser = [
                SELECT Id
                FROM User
                WHERE Username = :DEPLOY_USER_USERNAME
                AND IsActive = true
                LIMIT 1
            ];
            if (!deployUser.isEmpty()) {
                testHealthCloudUser = deployUser[0];
                return testHealthCloudUser;
            }
            testHealthCloudUser = createTestHealthCloudAdminUser();
            return testHealthCloudUser;
        }

        List<User> deployUser = [
            SELECT Id
            FROM User
            WHERE Username = :DEPLOY_USER_USERNAME
            AND IsActive = true
            LIMIT 1
        ];
        if (!deployUser.isEmpty()) {
            return deployUser[0];
        }

        List<User> hcAdmins = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND Id IN (
                SELECT AssigneeId
                FROM PermissionSetAssignment
                WHERE PermissionSet.Name = 'HealthCloudAdmin'
            )
            LIMIT 1
        ];
        if (!hcAdmins.isEmpty()) {
            return hcAdmins[0];
        }

        return [
            SELECT Id
            FROM User
            WHERE Profile.Name = 'System Administrator'
            AND IsActive = true
            LIMIT 1
        ];
    }

    private static User createTestHealthCloudAdminUser() {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        String uniq = String.valueOf(System.now().getTime());
        User testUser = new User(
            FirstName = 'WellSky',
            LastName = 'DeployTest',
            Alias = ('ws' + uniq.right(6)).left(8),
            Email = 'wellsky.deploy.test+' + uniq + '@example.com',
            Username = 'wellsky.deploy.test+' + uniq + '@cloudodyssey.co.wellspring.test',
            CommunityNickname = ('ws' + uniq.right(8)).left(8),
            TimeZoneSidKey = 'America/Detroit',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = adminProfile.Id
        );
        insert testUser;
        assignHealthCloudPermissionSets(testUser.Id);
        return testUser;
    }

    private static void assignHealthCloudPermissionSets(Id userId) {
        Set<String> permSetNames = new Set<String>{
            'HealthCloudAdmin',
            'HealthCloudPermissionSetLicense'
        };
        List<PermissionSet> permSets = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :permSetNames
        ];
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet ps : permSets) {
            assignments.add(
                new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id)
            );
        }
        if (!assignments.isEmpty()) {
            insert assignments;
        }
    }

    public static void ensureHealthCloudAdminForDeployUser() {
        healthCloudPermEnsured = true;
    }

    public static String getFirstActivePicklistValue(Schema.SObjectField field) {
        return getFirstActivePicklistValue(field.getDescribe());
    }

    public static String getFirstActivePicklistValue(Schema.DescribeFieldResult fieldDescribe) {
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    public static String getReferralTypeValue() {
        return getReferralTypeValue('Hospital');
    }

    public static String getReferralTypeValue(String preferredApiValue) {
        if (String.isNotBlank(preferredApiValue)) {
            for (Schema.PicklistEntry entry : Contact.ReferralType__c.getDescribe().getPicklistValues()) {
                if (entry.isActive() && entry.getValue().equalsIgnoreCase(preferredApiValue)) {
                    return entry.getValue();
                }
            }
        }
        return getFirstActivePicklistValue(Contact.ReferralType__c);
    }

    public static String getAccountLocationValue() {
        return getAccountLocationValue(null);
    }

    public static String getAccountLocationValue(Id recordTypeId) {
        if (recordTypeId == null) {
            return getFirstActivePicklistValue(Account.Location_g__c);
        }
        for (Schema.PicklistEntry entry : Account.Location_g__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            Account probe = new Account(
                LastName = 'LocProbe',
                RecordTypeId = recordTypeId,
                Location_g__c = entry.getValue()
            );
            try {
                insert probe;
                String value = probe.Location_g__c;
                delete probe;
                return value;
            } catch (DmlException e) {
                continue;
            }
        }
        return null;
    }

    public static String getBillingLocationValue() {
        return getFirstActivePicklistValue(Billing__c.Location_g__c);
    }

    public static String getAccountStatusValue(String preferredApiValue) {
        if (String.isBlank(preferredApiValue)) {
            return getFirstActivePicklistValue(Account.Account_Status__c);
        }
        for (Schema.PicklistEntry entry : Account.Account_Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue().equalsIgnoreCase(preferredApiValue)) {
                return entry.getValue();
            }
        }
        return getFirstActivePicklistValue(Account.Account_Status__c);
    }

    public static void disableTriggers() {
        setRunTriggers(false);
    }

    public static void enableTriggers() {
        setRunTriggers(true);
    }

    private static void setRunTriggers(Boolean runTriggers) {
        WellSky_Custom_Setting__c setting = WellSky_Custom_Setting__c.getOrgDefaults();
        if (setting == null || setting.Id == null) {
            insert new WellSky_Custom_Setting__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Run_Triggers__c = runTriggers
            );
        } else {
            setting.Run_Triggers__c = runTriggers;
            update setting;
        }
        TriggerControlUtil.reset();
    }

    public static Id getOrCreateReciprocalRoleId() {
        return getOrCreateReciprocalRoleForReferralType(getReferralTypeValue());
    }

    public static Id getOrCreateReciprocalRoleForReferralType(String referralType) {
        if (String.isBlank(referralType)) {
            referralType = getReferralTypeValue();
        }

        List<HealthCloudGA__ReciprocalRole__c> existing = [
            SELECT Id
            FROM HealthCloudGA__ReciprocalRole__c
            WHERE Name = :referralType
            AND HealthCloudGA__InverseRelationship__c != null
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        Id contactRoleRtId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();

        String inverseName = 'Inverse ' + referralType;
        HealthCloudGA__ReciprocalRole__c roleA = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = referralType,
            HealthCloudGA__InverseRole__c = inverseName
        );
        HealthCloudGA__ReciprocalRole__c roleB = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = inverseName,
            HealthCloudGA__InverseRole__c = referralType
        );
        insert new List<HealthCloudGA__ReciprocalRole__c>{ roleA, roleB };
        roleA.HealthCloudGA__InverseRelationship__c = roleB.Id;
        roleB.HealthCloudGA__InverseRelationship__c = roleA.Id;
        update new List<HealthCloudGA__ReciprocalRole__c>{ roleA, roleB };
        return roleA.Id;
    }

    public static Id getOrCreateFamilyContactRoleId() {
        for (String roleName : new List<String>{ 'Family Contact', 'Contact' }) {
            List<HealthCloudGA__ReciprocalRole__c> roles = [
                SELECT Id
                FROM HealthCloudGA__ReciprocalRole__c
                WHERE Name = :roleName
                AND HealthCloudGA__InverseRelationship__c != null
                LIMIT 1
            ];
            if (!roles.isEmpty()) {
                return roles[0].Id;
            }
        }
        return getOrCreateReciprocalRolePair('Family Contact', 'Contact');
    }

    public static Id getOrCreateCoupleHouseholdRoleId() {
        for (String roleName : new List<String>{ 'Spouse', 'Partner' }) {
            List<HealthCloudGA__ReciprocalRole__c> roles = [
                SELECT Id
                FROM HealthCloudGA__ReciprocalRole__c
                WHERE Name = :roleName
                AND HealthCloudGA__InverseRelationship__c != null
                LIMIT 1
            ];
            if (!roles.isEmpty()) {
                return roles[0].Id;
            }
        }
        return getOrCreateReciprocalRolePair('Spouse', 'Partner');
    }

    private static Id getOrCreateReciprocalRolePair(String nameA, String nameB) {
        List<HealthCloudGA__ReciprocalRole__c> existing = [
            SELECT Id
            FROM HealthCloudGA__ReciprocalRole__c
            WHERE Name = :nameA
            AND HealthCloudGA__InverseRelationship__c != null
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        Id contactRoleRtId = Schema.SObjectType.HealthCloudGA__ReciprocalRole__c
            .getRecordTypeInfosByDeveloperName()
            .get('ContactRole')
            .getRecordTypeId();

        HealthCloudGA__ReciprocalRole__c roleA = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = nameA,
            HealthCloudGA__InverseRole__c = nameB
        );
        HealthCloudGA__ReciprocalRole__c roleB = new HealthCloudGA__ReciprocalRole__c(
            RecordTypeId = contactRoleRtId,
            Name = nameB,
            HealthCloudGA__InverseRole__c = nameA
        );
        insert new List<HealthCloudGA__ReciprocalRole__c>{ roleA, roleB };
        roleA.HealthCloudGA__InverseRelationship__c = roleB.Id;
        roleB.HealthCloudGA__InverseRelationship__c = roleA.Id;
        update new List<HealthCloudGA__ReciprocalRole__c>{ roleA, roleB };
        return roleA.Id;
    }

    private static void insertCcrInTestContext(HealthCloudGA__ContactContactRelation__c ccr) {
        try {
            WellSkyCcrDmlService.insertCcr(ccr);
        } catch (DmlException firstAttempt) {
            if (firstAttempt.getMessage() == null
                || !firstAttempt.getMessage().contains('level of access required')) {
                throw firstAttempt;
            }
            //System.enqueueJob(new WellSkyCcrInsertQueueable(ccr));
            Test.startTest();
            Test.stopTest();
            List<HealthCloudGA__ContactContactRelation__c> inserted = [
                SELECT Id
                FROM HealthCloudGA__ContactContactRelation__c
                WHERE HealthCloudGA__Contact__c = :ccr.HealthCloudGA__Contact__c
                AND HealthCloudGA__RelatedContact__c = :ccr.HealthCloudGA__RelatedContact__c
                LIMIT 1
            ];
            if (inserted.isEmpty()) {
                throw firstAttempt;
            }
            ccr.Id = inserted[0].Id;
        }
    }

    private static void ensureContactsOwnedByDeployUser(Set<Id> contactIds) {
        if (!Test.isRunningTest() || contactIds == null || contactIds.isEmpty()) {
            return;
        }
        Id deployUserId = getAdminUser().Id;
        List<Contact> contacts = [
            SELECT Id, OwnerId
            FROM Contact
            WHERE Id IN :contactIds
        ];
        List<Contact> toUpdate = new List<Contact>();
        for (Contact c : contacts) {
            if (c.OwnerId != deployUserId) {
                toUpdate.add(new Contact(Id = c.Id, OwnerId = deployUserId));
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static void ensureBusinessContactReferralType(Id contactId, String referralType) {
        if (!Schema.SObjectType.Contact.fields.getMap().containsKey('ReferralType__c')) {
            return;
        }
        Contact businessContact = [
            SELECT Id, ReferralType__c
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];
        if (String.isBlank(businessContact.ReferralType__c)) {
            businessContact.ReferralType__c = referralType;
            update businessContact;
        }
    }

    private static Id resolveBusinessCcrRole(Id contactId, Id roleId) {
        String referralType = getReferralTypeValue('Hospital');
        ensureBusinessContactReferralType(contactId, referralType);
        return getOrCreateReciprocalRoleForReferralType(referralType);
    }

    public static HealthCloudGA__ContactContactRelation__c buildCcr(
        Id contactId,
        Id relatedContactId,
        Id roleId,
        String relationshipStatus
    ) {
        return buildCcr(contactId, relatedContactId, roleId, relationshipStatus, 'Business Contact');
    }

    public static HealthCloudGA__ContactContactRelation__c buildCcr(
        Id contactId,
        Id relatedContactId,
        Id roleId,
        String relationshipStatus,
        String ccrType
    ) {
        HealthCloudGA__ContactContactRelation__c ccr = new HealthCloudGA__ContactContactRelation__c(
            HealthCloudGA__Contact__c = contactId,
            HealthCloudGA__RelatedContact__c = relatedContactId,
            HealthCloudGA__Role__c = roleId
        );
        if (String.isNotBlank(relationshipStatus)) {
            ccr.Relationship_Status__c = relationshipStatus;
        }
        if (String.isNotBlank(ccrType)
            && Schema.SObjectType.HealthCloudGA__ContactContactRelation__c.fields.getMap()
                .containsKey('Type__c')) {
            ccr.Type__c = ccrType;
        }
        if (Schema.SObjectType.HealthCloudGA__ContactContactRelation__c.fields.getMap()
            .containsKey('HealthCloudGA__Active__c')) {
            ccr.put('HealthCloudGA__Active__c', true);
        }
        return ccr;
    }

    public static HealthCloudGA__ContactContactRelation__c insertCcr(
        Id contactId,
        Id relatedContactId,
        Id roleId,
        String relationshipStatus
    ) {
        return insertCcr(contactId, relatedContactId, roleId, relationshipStatus, 'Business Contact');
    }

    public static HealthCloudGA__ContactContactRelation__c insertCcrWithoutType(
        Id contactId,
        Id relatedContactId,
        Id roleId,
        String relationshipStatus
    ) {
        return insertCcr(contactId, relatedContactId, roleId, relationshipStatus, null);
    }

    public static HealthCloudGA__ContactContactRelation__c insertCcr(
        Id contactId,
        Id relatedContactId,
        Id roleId,
        String relationshipStatus,
        String ccrType
    ) {
        HealthCloudGA__ContactContactRelation__c ccr;
        //System.runAs(getAdminUser()) {
            //ensureHealthCloudAdminForDeployUser();
            //disableTriggers();

            if (roleId == null) {
                if ('Couple Household'.equals(ccrType)) {
                    roleId = getOrCreateCoupleHouseholdRoleId();
                } else if ('Family Contact'.equals(ccrType)) {
                    roleId = getOrCreateFamilyContactRoleId();
                } else {
                    roleId = getOrCreateReciprocalRoleId();
                }
            }

            if ('Business Contact'.equals(ccrType)) {
                roleId = resolveBusinessCcrRole(contactId, roleId);
            }

            ensureContactsOwnedByDeployUser(
                new Set<Id>{ contactId, relatedContactId }
            );

            ccr = buildCcr(contactId, relatedContactId, roleId, relationshipStatus, ccrType);
            try {
                if (Test.isRunningTest()) {
                    insertCcrInTestContext(ccr);
                } else {
                    insert ccr;
                }
            } catch (DmlException e) {
                if (Test.isRunningTest()
                    && e.getMessage() != null
                    && e.getMessage().contains('level of access required')) {
                    List<HealthCloudGA__ContactContactRelation__c> existing = [
                        SELECT Id
                        FROM HealthCloudGA__ContactContactRelation__c
                        WHERE HealthCloudGA__Contact__c = :contactId
                        AND HealthCloudGA__RelatedContact__c = :relatedContactId
                        LIMIT 1
                    ];
                    if (!existing.isEmpty()) {
                        return existing[0];
                    }
                }
                throw e;
            }
        //}
        return ccr;
    }
}