/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : EventBillingScheduler
CreatedOn      : 30-04-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This scheduler class is used to execute the EventBillingBatch
                 asynchronously at scheduled intervals for generating Billing
                 and Billing Line Item records from completed Events.
----------------------------------------------------------------------------
*/
public class EventBillingScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {

        EventBillingBatch batch = new EventBillingBatch();
        Database.executeBatch(batch, 200);
    }
}