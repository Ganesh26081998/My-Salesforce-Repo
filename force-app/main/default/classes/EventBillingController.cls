/*
----------------------------------------------------------------------------
Author        : Ankit Pande
Class Name    : EventBillingController
CreatedOn     : 20-03-2026
LastModifiedOn: 09-06-2026
LastModifiedBy: Ankit Pande
Description   : This class is used to manage Event Billing processing by
 *                 executing asynchronous billing jobs, tracking queueable job
 *                 status, preventing duplicate job execution, and retrieving
 *                 completed events that are pending for billing generation.
----------------------------------------------------------------------------
*/

public with sharing class EventBillingController {

    @AuraEnabled
    public static String runJob(Date startDate, Date endDate) {

        if (isJobRunning()) {
            return 'ALREADY_RUNNING';
        }

        Id jobId = System.enqueueJob(new EventBillingQueueable(startDate, endDate));
        return jobId;
    }

    public class JobStatusWrapper {
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=false)
    public static JobStatusWrapper getJobStatus(Id jobId) {

        if (jobId == null) return null;

        AsyncApexJob job = [
            SELECT Status, CreatedDate
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];

        JobStatusWrapper wrap = new JobStatusWrapper();
        wrap.status = job.Status;
        wrap.createdDate = job.CreatedDate;

        return wrap;
    }

    private static Boolean isJobRunning() {

        List<AsyncApexJob> jobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'EventBillingQueueable'
            AND Status IN ('Processing', 'Queued')
        ];

        return !jobs.isEmpty();
    }

    @AuraEnabled(cacheable=false)
public static List<Event> getPendingBillingEvents(
    Integer limitSize,
    Integer offsetVal,
    Date startDate,
    Date endDate
) {

    //  CHANGE: Get person account Contact Ids first via subquery
    Set<Id> personAccountContactIds = new Map<Id, Contact>([
        SELECT Id 
        FROM Contact 
        WHERE IsPersonAccount = true
    ]).keySet();

    String query = 'SELECT Id, Subject, StartDateTime, EndDateTime, Status__c, ' +
                   'IsAllDayEvent, Who.Name, What.Name ' +
                   'FROM Event WHERE Status__c = \'Completed\' ' +
                   'AND Billing__c = NULL ' +
                   'AND IsChild = false ' +
                   'AND WhoId IN :personAccountContactIds '; //  CHANGE: Only person account events

    if (startDate != null) {
        query += ' AND DAY_ONLY(StartDateTime) >= :startDate';
    }

    if (endDate != null) {
        query += ' AND DAY_ONLY(EndDateTime) <= :endDate';
    }

    query += ' ORDER BY StartDateTime DESC LIMIT :limitSize OFFSET :offsetVal';

    return Database.query(query);
}
}