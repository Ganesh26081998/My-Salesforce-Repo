/*
----------------------------------------------------------------------------
Author         : Ganesh Uppin
Class Name     : WeeklyCapacityScheduler
CreatedOn      : 13-01-2026
LastModifiedOn : 10-05-2026
LastModifiedBy : Ganesh Uppin

Description    : This schedulable class is used to automatically trigger the
                 Weekly Capacity batch process at scheduled intervals. It
                 executes the WeeklyCapacityBatch to calculate and update
                 weekly capacity records for Care Managers.
----------------------------------------------------------------------------
*/
global class WeeklyCapacityScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        WeeklyCapacityBatch batch = new WeeklyCapacityBatch();
        Database.executeBatch(batch, 200);
    }
}