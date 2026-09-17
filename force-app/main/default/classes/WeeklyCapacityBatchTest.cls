@isTest
private class WeeklyCapacityBatchTest {

    private static Event createEventForUser(Date eventDate, Integer startHour, Integer durationHours, Id careManagerId) {
        Datetime startDt = Datetime.newInstance(eventDate, Time.newInstance(startHour, 0, 0, 0));
        Datetime endDt   = startDt.addHours(durationHours);

        return new Event(
            Subject = 'Weekly Capacity Test Event',
            StartDateTime = startDt,
            EndDateTime = endDt,
            Care_Manager__c = careManagerId
        );
    }

    @isTest
    static void testBatch_InsertsCapacityAndClosesPastWeeks() {
        Id userId = UserInfo.getUserId();

        // Past open week -> should become Closed in finish()
        Capacity_Week__c pastWeek = new Capacity_Week__c(
            Week_Start_Date__c = Date.today().addDays(-14).toStartOfWeek(),
            Week_Ends_Date__c = Date.today().addDays(-1),
            Status__c = 'Open'
        );
        insert pastWeek;

        // Event in next 30 days -> should create/update current week capacity
        Date eventDate = Date.today().addDays(3);
        insert createEventForUser(eventDate, 9, 2, userId); // 2 hours

        Test.startTest();
        Database.executeBatch(new WeeklyCapacityBatch(), 50);
        Test.stopTest();

        Date expectedWeekStart = eventDate.toStartOfWeek();

        Capacity_Week__c currentWeek = [
            SELECT Id, Week_Start_Date__c, Week_Ends_Date__c, Status__c
            FROM Capacity_Week__c
            WHERE Week_Start_Date__c = :expectedWeekStart
            LIMIT 1
        ];

        User_Weekly_Capacity__c uwc = [
            SELECT Id, User__c, Capacity_Week__c, Actual_Scheduled_Hours__c
            FROM User_Weekly_Capacity__c
            WHERE User__c = :userId AND Capacity_Week__c = :currentWeek.Id
            LIMIT 1
        ];

        System.assertEquals(2, uwc.Actual_Scheduled_Hours__c, 'Scheduled hours should be calculated from Event duration.');

        pastWeek = [SELECT Id, Status__c FROM Capacity_Week__c WHERE Id = :pastWeek.Id];
        System.assertEquals('Closed', pastWeek.Status__c, 'Past open week should be closed in finish().');
    }

    @isTest
    static void testBatch_UpdatesExistingUserWeeklyCapacity() {
        Id userId = UserInfo.getUserId();

        Date eventDate = Date.today().addDays(5);
        Date weekStart = eventDate.toStartOfWeek();

        Capacity_Week__c week = new Capacity_Week__c(
            Week_Start_Date__c = weekStart,
            Week_Ends_Date__c = weekStart.addDays(6),
            Status__c = 'Open'
        );
        insert week;

        // Existing record should be updated (not duplicated)
        insert new User_Weekly_Capacity__c(
            User__c = userId,
            Capacity_Week__c = week.Id,
            Actual_Scheduled_Hours__c = 1
        );

        insert createEventForUser(eventDate, 10, 3, userId); // 3 hours

        Test.startTest();
        Database.executeBatch(new WeeklyCapacityBatch(), 50);
        Test.stopTest();

        List<User_Weekly_Capacity__c> rows = [
            SELECT Id, Actual_Scheduled_Hours__c
            FROM User_Weekly_Capacity__c
            WHERE User__c = :userId AND Capacity_Week__c = :week.Id
        ];

        System.assertEquals(1, rows.size(), 'Batch should update existing weekly capacity, not insert duplicate.');
        System.assertEquals(3, rows[0].Actual_Scheduled_Hours__c, 'Existing record should be updated with recalculated hours.');
    }
}