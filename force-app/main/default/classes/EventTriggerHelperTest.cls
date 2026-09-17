/*
----------------------------------------------------------------------------
Author        : Ankit Pande
Class Name    : EventRateSyncController
CreatedOn     : 13-03-2026
LastModifiedOn: 15-03-2026
LastModifiedBy: Ankit Pande
Description   : This class is used to sync rate calculation details, mileage,
 *                 expense information, client billing details, and caregiver
 *                 billing details from a recurring source event to all related
 *                 recurring events.
----------------------------------------------------------------------------
*/
@IsTest
public class EventTriggerHelperTest {

    @IsTest
    static void testStaticVariable() {

        // Default value check
        System.assertEquals(false, EventTriggerHelper.isRunning);

        // Change value
        EventTriggerHelper.isRunning = true;

        // Verify updated value
        System.assertEquals(true, EventTriggerHelper.isRunning);
    }
}