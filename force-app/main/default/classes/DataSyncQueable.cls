public with sharing class DataSyncQueable implements Queueable, Database.AllowsCallouts {
    
    private boolean isContinuation = false;
    
    public DataSyncQueable(boolean isContinuation) {
        this.isContinuation = isContinuation;
    }
    
    public void execute(QueueableContext context) {
        
        List<Data_Sync_Job__c> pendingChanges = new List<Data_Sync_Job__c>();
        
        try {
            if (!this.isContinuation) {
                // We need to make sure the old chain from 15 minutes ago isn't still running.
                // This could happen if the system was down and a lot of changes are pending
                // and they could not all be processed within the 15 minute window.
                List<AsyncApexJob> processingJobs = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedDate, CompletedDate, ExtendedStatus 
                    FROM AsyncApexJob 
                    WHERE JobType = 'Queueable'
                    AND ApexClass.Name = 'DataSyncQueable'
                    AND Status IN ('Processing', 'Preparing') 
                    AND Id != :context.getJobId()
                    ORDER BY CreatedDate DESC
                    LIMIT 1];
                
                if (!processingJobs.isEmpty()) {
                    // Another instanace is already running, so exit
                    DataSyncUtility.CreateApplicationLog('Info', 'This job did not run because another one is still running: ' + processingJobs[0].Id, 'execute', 'FastFieldSyncQueable');
                    return;
                }
            }
            
            // Retrieve records with status = 'Pending' and 'Retry'.   We just get all the fields so they are available to the handler.
            // In most project, we try to sync records in the order they were created.  If there is a Retry we intend to have it 
            // block processing the next record to make sure the order is maintained.   On some projects we might not Retry records
            // to block new Pending records.    We assume Retry only happens when there is a system outage.  If it was just bad data
            // the status should be Abort.
            pendingChanges = [SELECT 
                    Id, 
                    Status__c,
                    Retry_Attempts__c,
                    External_System__c,
                    Method_Type__c,
                    Service_URL__c,
                    Total_Number_Of_Page__c,
                    Page_Number__c,
                    Per_Page_Record_Count__c,
                    Is_More_Records__c,
                    Related_Record_Id__c,
                    
                    Config__r.Name, 
                    Config__r.Method__c, 
                    Config__r.Service_Path__c, 
                    Config__r.Response_Is_Paged__c, 
                    Config__r.Rows_Per_Page_Field_Name__c, 
                    Config__r.Current_Page_Field_Name__c, 
                    Config__r.External_System__c, 
                    Config__r.Callout_Class_Name__c, 
                    Config__r.Processor_Class_Name__c, 
                    Config__r.Rows_Per_Page__c,
                    Config__r.Salesforce_Object_Name__c,
                    Config__r.Total_Record_Path__c,
                    Config__r.Response_Paged_Array_Path__c,
                    Config__r.Service_Path_Id_Field_Name__c,
                    
                    Callback_Response_Config__r.Name, 
                    Callback_Response_Config__r.Method__c, 
                    Callback_Response_Config__r.Service_Path__c, 
                    Callback_Response_Config__r.Response_Is_Paged__c, 
                    Callback_Response_Config__r.Rows_Per_Page_Field_Name__c, 
                    Callback_Response_Config__r.Current_Page_Field_Name__c, 
                    Callback_Response_Config__r.External_System__c, 
                    Callback_Response_Config__r.Callout_Class_Name__c, 
                    Callback_Response_Config__r.Processor_Class_Name__c, 
                    Callback_Response_Config__r.Rows_Per_Page__c,
                    Callback_Response_Config__r.Salesforce_Object_Name__c,
                    Callback_Response_Config__r.Total_Record_Path__c,
                    Callback_Response_Config__r.Response_Paged_Array_Path__c,
                    Callback_Response_Config__r.Service_Path_Id_Field_Name__c
                    
                FROM Data_Sync_Job__c 
                WHERE (Status__c IN ('Pending', 'Retry'))
                ORDER BY CreatedDate ASC
                LIMIT 1];  // We only do things 1 at a time.
      
            if (pendingChanges.size() == 0) {
                // No records to process
                return;
            }
            
            // Do the work here.  If there is a critical error we expect it to throw an exception.
            Data_Sync_Job__c pendingChange = pendingChanges[0];
            if (pendingChange.Status__c == 'Retry') {
                if (pendingChange.Retry_Attempts__c == null) {
                    pendingChange.Retry_Attempts__c = 1;
                } else {
                    pendingChange.Retry_Attempts__c += 1;
                }
            }
            DataSyncInterfaces.IDataSyncProcessor processor = (DataSyncInterfaces.IDataSyncProcessor) Type.forName(pendingChange.Config__r.Processor_Class_Name__c).newInstance();
            processor.processSync(pendingChanges[0]);
            
            // We assume the processSync updates the status.
            
            // Since there were record found, and everything went well (no error was thrown) we will run again in case there are more.
            // This continues until there is nothing left to process.
            // Max chain depth is 5 in a dev org. 
            try {
                if(System.AsyncInfo.hasMaxStackDepth() &&
                System.AsyncInfo.getCurrentQueueableStackDepth() >= 
                System.AsyncInfo.getMaximumQueueableStackDepth()) {
                    return;
                }
                DataSyncQueable job = new DataSyncQueable(true);
                System.enqueueJob(job);
            } catch (Exception e) {
                // the rest of the records will get processed on the hour.
            }
            
            
        } catch (Exception e) {
            DataSyncUtility.CreateApplicationLog('Error','Line: ' + e.getLineNumber() + '\n' + e.getMessage(), 'execute Last', 'DataSyncQueable');
            
            // Update the Data_Sync_Job__c to be Status=Failed
            if (pendingChanges.size() > 0) {
                Data_Sync_Job__c failedRecord = new Data_Sync_Job__c();
                failedRecord.Id = pendingChanges[0].Id;
                failedRecord.Status__c = 'Abort';
                update failedRecord;
            }
            
        }
    }
    
    
}