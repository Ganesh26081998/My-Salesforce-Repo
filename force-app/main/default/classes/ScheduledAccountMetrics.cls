global class ScheduledAccountMetrics implements Schedulable {
    global void execute(SchedulableContext sc) {
        // Run the batch with a standard batch size of 200
        Database.executeBatch(new BusinessAccountMetricsBatch(), 200);
    }
}