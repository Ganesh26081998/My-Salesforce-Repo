global class DataSyncProcessRecordsPaginationBatch implements Database.Batchable<sObject>, Database.AllowsCallouts,Database.Stateful{ 
    Private Integer pageCount;
    Private Integer totalPage;
    Private Data_Sync_Job__c pendingChange;
    public DataSyncProcessRecordsPaginationBatch(integer pageCount,Integer totalPage,Data_Sync_Job__c pendingChange) {
        System.debug('Cons pageCount::'+pageCount);
        this.pageCount = pageCount;
        this.totalPage = totalPage;
        this.pendingChange = pendingChange;

}

global Database.QueryLocator start(Database.BatchableContext BC) {
   
    String query = 'SELECT Id FROM Data_Sync_Job__c where Id = \'' + this.pendingChange.Id + '\' order by Id ASC';
    System.debug('query:'+query);
    return Database.getQueryLocator(query);
}

global void execute(Database.BatchableContext BC, List<Data_Sync_Job__c> pendingChangeList) {
   // TODO do rest page callout and map the fields
    System.debug('pageCount::'+this.pageCount);
    System.debug('totalPage::'+this.totalPage);
    this.pageCount = this.pageCount + 1;
}   

global void finish(Database.BatchableContext BC) {
    if(this.totalPage == this.pageCount ){
        //this.pendingChange.Response__c = (DataSyncProcessor.oldResponse)?.getBody()?.left(13172);
        this.pendingChange.Status__c = 'Complete';
        update this.pendingChange;
        return;
    }
    DataSyncProcessRecordsPaginationBatch job = new DataSyncProcessRecordsPaginationBatch(this.pageCount,this.totalPage,this.pendingChange);
    database.executeBatch(job);
}
 }