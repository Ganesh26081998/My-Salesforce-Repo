/*
----------------------------------------------------------------------------
Author         : Ganesh Uppin
Class Name     : WeeklyCapacityController
CreatedOn      : 13-01-2026
LastModifiedOn : 10-05-2026
LastModifiedBy : Ganesh Uppin

Description    : This controller class is used to trigger the Weekly Capacity
                 batch process manually from Lightning components. It starts
                 the batch execution to calculate and update weekly capacity
                 records for Care Managers based on scheduled Events.
----------------------------------------------------------------------------
*/
public with sharing class WeeklyCapacityController {

    @AuraEnabled
    public static void runBatch() {
        Database.executeBatch(new WeeklyCapacityBatch(), 200);
    }
}