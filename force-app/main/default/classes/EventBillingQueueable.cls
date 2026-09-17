/*
----------------------------------------------------------------------------
Author        : Ankit Pande
Class Name    : EventBillingQueueable
CreatedOn     : 20-03-2026
LastModifiedOn: 09-06-2026
LastModifiedBy: Ankit Pande
Description   : This class is used to manage Event Billing processing by
 *                 executing asynchronous billing jobs, tracking queueable job
 *                 status, preventing duplicate job execution, and retrieving
 *                 completed events that are pending for billing generation.
----------------------------------------------------------------------------
*/
public class EventBillingQueueable implements Queueable {

    //  ADDED: Date filter fields
    private Date startDate;
    private Date endDate;

    //  ADDED: No-arg constructor (keeps backward compatibility)
    public EventBillingQueueable() {
        this.startDate = null;
        this.endDate = null;
    }

    //  ADDED: Date constructor — called by EventBillingController.runJob()
    public EventBillingQueueable(Date startDate, Date endDate) {
        this.startDate = startDate;
        this.endDate = endDate;
    }

    public void execute(QueueableContext context) {
        //  CHANGED: Pass dates into batch so it only processes selected date records
        EventBillingBatch batch = new EventBillingBatch(startDate, endDate);
        Database.executeBatch(batch, 200);
    }
}