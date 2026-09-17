/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : TriggerControlUtil
CreatedOn      : 30-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This utility class is used to control trigger execution
                 based on organization-level custom settings. It provides
                 centralized logic to determine whether triggers should run
                 and includes a reset method for test execution support.
----------------------------------------------------------------------------
*/
public class TriggerControlUtil {

	private static Boolean runTriggers;

	public static Boolean shouldRun() {
        if (runTriggers == null) {
            WellSky_Custom_Setting__c setting = WellSky_Custom_Setting__c.getOrgDefaults();
            runTriggers = (setting != null && setting.Run_Triggers__c);
        }
        return runTriggers;
    }
    
    @TestVisible
    private static void reset() {
        runTriggers = null;
    }

}