/*
----------------------------------------------------------------------------
Author         : Narayana Raja Bommidi
Class Name     : InvoicesCleanupScheduler
CreatedOn      : 07-05-2026
LastModifiedOn : 21-05-2026
LastModifiedBy : Narayana Raja Bommidi
Description    : This scheduler class is used to execute the
                 InvoicesCleanupBatch asynchronously at scheduled intervals
                 for removing old Invoice records and retaining only the
                 latest configured invoices.
----------------------------------------------------------------------------
*/
global class InvoicesCleanupScheduler implements Schedulable {
	public void execute(SchedulableContext sc) {
		Database.executeBatch( new InvoicesCleanupBatch(), 200 );
	}
}