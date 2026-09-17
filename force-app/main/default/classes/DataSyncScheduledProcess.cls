//DataSyncScheduledProcess.scheduleProcess();
public class DataSyncScheduledProcess implements Schedulable {
    public void execute(SchedulableContext SC) {
        DataSyncQueable job = new DataSyncQueable(false);
        System.enqueueJob(job);
    }
    public void scheduleProcess(){
        //This is code to delete all the schedules and then just schedule one...
        List<CronTrigger> cronTriggers = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name like 'Data Sync Process%'];
        for (CronTrigger cronTrigger: cronTriggers ) {
            System.abortJob(cronTrigger.id);
        }
        //for every 15 mins
        System.schedule('Data Sync Process', '0 0 * * * ?', new DataSyncScheduledProcess());
        System.schedule('Data Sync Process', '0 15 * * * ?', new DataSyncScheduledProcess());
        System.schedule('Data Sync Process', '0 30 * * * ?', new DataSyncScheduledProcess());
        System.schedule('Data Sync Process', '0 45 * * * ?', new DataSyncScheduledProcess());
    }
}