public class WellSkyCcrInsertQueueable implements Queueable {

    private final HealthCloudGA__ContactContactRelation__c ccrRecord;

    public WellSkyCcrInsertQueueable(HealthCloudGA__ContactContactRelation__c ccrRecord) {
        this.ccrRecord = ccrRecord;
    }

    public void execute(QueueableContext context) {
        WellSkyCcrDmlService.insertCcr(ccrRecord);
    }
}