/*
----------------------------------------------------------------------------
Author         : Ganesh Uppin
Class Name     : WeeklyCapacityBatch
CreatedOn      : 13-01-2026
LastModifiedOn : 10-05-2026
LastModifiedBy : Ganesh Uppin

Description    : This batch class is used to calculate and manage weekly
                 capacity records for Care Managers based on scheduled Event
                 hours. It creates missing Capacity Weeks, updates User
                 Weekly Capacity records, and automatically closes expired
                 Capacity Weeks.
----------------------------------------------------------------------------
*/
global class WeeklyCapacityBatch implements Database.Batchable<SObject>, Database.Stateful {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('Batch started');
        // Fetch events for next 30 days (you can increase if needed)
        Date today = Date.today();
        Date futureDate = today.addDays(30);

        Datetime startDT = Datetime.newInstance(today, Time.newInstance(0,0,0,0));
        Datetime endDT   = Datetime.newInstance(futureDate, Time.newInstance(23,59,59,999));

        return Database.getQueryLocator([
            SELECT Id, Care_Manager__c, StartDateTime, EndDateTime
            FROM Event
            WHERE Care_Manager__c != NULL
            AND StartDateTime <= :endDT
            AND EndDateTime >= :startDT
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Event> scope) {
        system.debug('Executing batch scope, size=' + scope.size());
        Map<String, Decimal> userWeekHoursMap = new Map<String, Decimal>();
        Set<Date> weekStartDates = new Set<Date>();
        Set<Id> userIds = new Set<Id>();

        // STEP 1: CALCULATE HOURS PER USER PER WEEK
        for (Event e : scope) {

            if (e.StartDateTime == null || e.EndDateTime == null) continue;

            Date eventDate = e.StartDateTime.date();
            Date weekStart = eventDate.toStartOfWeek();

            Decimal hours = (e.EndDateTime.getTime() - e.StartDateTime.getTime()) 
                            / (1000.0 * 60 * 60);

            String key = e.Care_Manager__c + '###' + weekStart;

            userWeekHoursMap.put(
                key,
                (userWeekHoursMap.containsKey(key) ? userWeekHoursMap.get(key) : 0) + hours
            );

            weekStartDates.add(weekStart);
            userIds.add(e.Care_Manager__c);
        }

        // STEP 2: GET EXISTING CAPACITY WEEKS
        Map<Date, Id> weekMap = new Map<Date, Id>();

        for (Capacity_Week__c cw : [
            SELECT Id, Week_Start_Date__c
            FROM Capacity_Week__c
            WHERE Week_Start_Date__c IN :weekStartDates
        ]) {
            weekMap.put(cw.Week_Start_Date__c, cw.Id);
        }
        system.debug('weekmap data'+weekMap);

        // STEP 3: CREATE MISSING WEEKS
        List<Capacity_Week__c> newWeeks = new List<Capacity_Week__c>();

        for (Date d : weekStartDates) {
            if (!weekMap.containsKey(d)) {
                newWeeks.add(new Capacity_Week__c(
                    Week_Start_Date__c = d,
                    Week_Ends_Date__c = d.addDays(6),
                    Status__c = 'Open'
                ));
            }
        }

        if (!newWeeks.isEmpty()) {
            insert newWeeks;

            for (Capacity_Week__c cw : newWeeks) {
                weekMap.put(cw.Week_Start_Date__c, cw.Id);
            }
        }

        // STEP 4: GET EXISTING USER WEEKLY CAPACITY
        Map<String, User_Weekly_Capacity__c> existingMap = new Map<String, User_Weekly_Capacity__c>();

        for (User_Weekly_Capacity__c uwc : [
            SELECT Id, User__c, Capacity_Week__c, Actual_Scheduled_Hours__c,
                   Capacity_Week__r.Week_Start_Date__c
            FROM User_Weekly_Capacity__c
            WHERE User__c IN :userIds
        ]) {
            String key = uwc.User__c + '###' + uwc.Capacity_Week__r.Week_Start_Date__c;
            existingMap.put(key, uwc);
        }

        List<User_Weekly_Capacity__c> toInsert = new List<User_Weekly_Capacity__c>();
        List<User_Weekly_Capacity__c> toUpdate = new List<User_Weekly_Capacity__c>();

        Map<Id, User> userMap = new Map<Id, User>([
        SELECT Id, Desired_Weekly_Hours__c
        FROM User
        WHERE Id IN :userIds
    ]);

        // STEP 5: UPSERT LOGIC
        for (String key : userWeekHoursMap.keySet()) {

            List<String> parts = key.split('###');
            Id userId = parts[0];
            Date weekStart = Date.valueOf(parts[1]);

            Id weekId = weekMap.get(weekStart);
            Decimal hours = userWeekHoursMap.get(key);

            if (existingMap.containsKey(key)) {

                User_Weekly_Capacity__c existing = existingMap.get(key);
                existing.Actual_Scheduled_Hours__c = hours;
                if(userMap.containsKey(userId)) {
                existing.Desired_Weekly_Hours__c = userMap.get(userId).Desired_Weekly_Hours__c;
            }
                toUpdate.add(existing);

            } else {

                toInsert.add(new User_Weekly_Capacity__c(
                    User__c = userId,
                    Capacity_Week__c = weekId,
                    Actual_Scheduled_Hours__c = hours,
                     Desired_Weekly_Hours__c = userMap.containsKey(userId) 
                    ? userMap.get(userId).Desired_Weekly_Hours__c 
                    : 0
                ));
            }
        }

        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    global void finish(Database.BatchableContext bc) {
        //System.debug('Weekly Capacity Batch Completed');
        List<Capacity_Week__c> weeksToClose = [
        SELECT Id, Week_Ends_Date__c, Status__c
        FROM Capacity_Week__c
        WHERE Week_Ends_Date__c < :Date.today()
        AND Status__c = 'Open'
    ];

    for (Capacity_Week__c cw : weeksToClose) {
        cw.Status__c = 'Closed';
    }

    if (!weeksToClose.isEmpty()) {
        update weeksToClose;
    }

    System.debug('Weekly Capacity Batch Completed');
}

    
}