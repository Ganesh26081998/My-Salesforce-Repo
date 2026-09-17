global class ContactReferralMetricsScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {

        // Run batch with safe batch size
        Database.executeBatch(new ContactReferralMetricsBatch(),200);
    }
}