import { LightningElement, wire, track } from 'lwc';
import getBillables from '@salesforce/apex/BillableListViewController.getBillables';
import syncSelectedBillings from '@salesforce/apex/BillingSyncLWCController.syncSelectedBillings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import { refreshApex } from '@salesforce/apex';
import getBatchStatus from '@salesforce/apex/BillingSyncLWCController.getBatchStatus';
const COLUMNS = [
    {
        label: 'Sr. No.',
        fieldName: 'srNo',
        type: 'text',
        fixedWidth: 80,
        cellAttributes: {
        alignment: 'center'
    }
    },
    {
        label: 'Billable ID',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'Name' },
            target: '_blank'
        }
    },
    {
        label: 'Client',
        fieldName: 'clientName',
        type: 'text'
    },
    {
        label: 'Invoice Amount',
        fieldName: 'Amount__c',
        type: 'currency',
         cellAttributes: {
        alignment: 'left'
    }
    },
    
    {
        label: 'QB Sync Status',
        fieldName: 'QB_Sync_Status__c',
        type: 'text'
    },
    {
        label: 'Created Date',
        fieldName: 'CreatedDate',
        type: 'date'
    },
    {
    label: 'Event Start Date',
    fieldName: 'Event_Start_Date_Time__c',
    type: 'date'
},
{
    label: 'Event End Date',
    fieldName: 'Event_End_Date_Time__c',
    type: 'date'
},
    {
        label: 'Owner',
        fieldName: 'ownerName',
        type: 'text'
    },
    {
        label: 'Location',
        fieldName: 'Location_g__c',
        type: 'text'
    },
    {
        label:'Last Modified Date',
        fieldName: 'LastModifiedDate',
        type: 'date'
    }
    
    
];

export default class CustomBillableListView extends LightningElement {

    columns = COLUMNS;
    selectedRows = [];
    selectedCount = 0;
    @track billables = [];
    @track filteredData = [];
    error;
    selectedLocation = 'All';
    searchKey = '';
    selectedStartDate;
    selectedEndDate;
    @track isLoading = false;
    wiredResult;
    @track isJobRunning = false;
    batchJobId;
    pollingInterval;

locationOptions = [
    { label: 'All', value: 'All' },
    { label: 'Milwaukee', value: 'Milwaukee' },
    { label: 'Detroit', value: 'Detroit' },
    { label: 'Cincinnati', value: 'Cincinnati' }
];
get today() {
    return new Date().toLocaleDateString('en-CA', {
        timeZone: TIME_ZONE
    });
}
    
handleLocationChange(event) {
    this.selectedLocation = event.detail.value;
    this.applyFilters();
}
// handleStartDateChange(event) {
//     this.selectedStartDate = event.target.value;
//     this.applyFilters();
// }

handleStartDateChange(event) {

    const selectedDate = event.target.value;

    // Validation 1: Future date not allowed
    if (selectedDate > this.today) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Invalid Date',
                message: 'Future dates are not allowed.',
                variant: 'error'
            })
        );

        event.target.value = this.selectedStartDate;
        return;
    }

    // Validation 2: Start Date should not be greater than End Date
    if (this.selectedEndDate && selectedDate > this.selectedEndDate) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Invalid Date Range',
                message: 'Event Start Date cannot be greater than Event End Date.',
                variant: 'error'
            })
        );

        event.target.value = this.selectedStartDate;
        return;
    }

    // Existing functionality
    this.selectedStartDate = selectedDate;
    this.applyFilters();
}

// handleEndDateChange(event) {
//     this.selectedEndDate = event.target.value;
//     this.applyFilters();
// }
handleEndDateChange(event) {

    const selectedDate = event.target.value;

    // Validation 1: Future date not allowed
    if (selectedDate > this.today) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Invalid Date',
                message: 'Future dates are not allowed.',
                variant: 'error'
            })
        );

        event.target.value = this.selectedEndDate;
        return;
    }

    // Validation 2: End Date should not be less than Start Date
    if (this.selectedStartDate && selectedDate < this.selectedStartDate) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Invalid Date Range',
                message: 'Event End Date cannot be less than Event Start Date.',
                variant: 'error'
            })
        );

        event.target.value = this.selectedEndDate;
        return;
    }

    // Existing functionality
    this.selectedEndDate = selectedDate;
    this.applyFilters();
}
get isSingleSelection() {
    return this.selectedCount === 1;
}

    /*@wire(getBillables)
    wiredBillables({ error, data }) {

        if (data) {

            this.billables = data.map((row,index) => ({
                ...row,
                srNo: index + 1,
                recordUrl: '/' + row.Id,
                clientName: row.Client__r ? row.Client__r.Name : '',
                ownerName: row.Owner ? row.Owner.Name : ''
            }));
            console.log('Billables:', JSON.stringify(this.billables));
            console.log('Raw Data:', JSON.stringify(data));
            if(data && data.length){
                console.log(data[0].LastModifiedDate);
            }
            //console.log('date value',data[0].LastModifiedDate);
            this.filteredData = [...this.billables];
            this.error = undefined;

        } else if (error) {
            this.error = error.body.message;
        }
    }*/
   @wire(getBillables)
wiredBillables(result) {

    this.wiredResult = result;

    const { error, data } = result;

    if (data) {

        this.billables = data.map((row,index) => ({
            ...row,
            srNo: index + 1,
            recordUrl: '/' + row.Id,
            clientName: row.Client__r ? row.Client__r.Name : '',
            ownerName: row.Owner ? row.Owner.Name : ''
        }));

        console.log('Billables:', JSON.stringify(this.billables));
        console.log('Raw Data:', JSON.stringify(data));

        if(data && data.length){
            console.log(data[0].LastModifiedDate);
        }

        this.filteredData = [...this.billables];
        this.error = undefined;

    } else if (error) {
        this.error = error.body.message;
    }
}

    
    handleSearch(event) {
    this.searchKey = event.target.value.toLowerCase().trim();
    this.applyFilters();
}
    handleRowSelection(event) {
    this.selectedRows = event.detail.selectedRows;
      this.selectedCount = this.selectedRows.length;
    console.log(
        'Selected Records:',
        JSON.stringify(this.selectedRows)
    );
}

/*async handleSelectedSync() {

    console.log('selected sync button clicked..!');

    const ids = this.selectedRows.map(row => row.Id);

    console.log('Selected Ids:', ids);

    if (!ids.length) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'No Records Selected',
                message: 'Please select at least one record to sync.',
                variant: 'warning'
            })
        );

        return;
    }

    try {

        await syncSelectedBillings({
            billingIds: ids
        });

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Billing sync has been queued successfully...!',
                variant: 'success'
            })
        );
        

    } catch(error) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Failed to start sync.',
                variant: 'error'
            })
        );
    }
}*/

async handleSelectedSync() {

    console.log('selected sync button clicked..!');

    const ids = this.selectedRows.map(row => row.Id);

    if (!ids.length) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'No Records Selected',
                message: 'Please select at least one record to sync.',
                variant: 'warning'
            })
        );

        return;
    }

    this.isLoading = true;

    try {

         this.batchJobId = await syncSelectedBillings({
            billingIds: ids
        });
        this.isJobRunning = true;
        this.startPolling();
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Synchronization Started',
                message: 'Billing synchronization has started successfully. Records are being processed in the background. Click Refresh to view the latest sync status.',
                variant: 'success'
            })
        );

    } catch(error) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Failed to start sync.',
                variant: 'error'
            })
        );

    } finally {

        this.isLoading = false;
    }
}
applyFilters() {

    this.filteredData = this.billables.filter(row => {

        const matchesSearch =
            !this.searchKey ||
            (row.Name || '').toLowerCase().includes(this.searchKey) ||
            (row.clientName || '').toLowerCase().includes(this.searchKey) ||
            (row.ownerName || '').toLowerCase().includes(this.searchKey);

        const matchesLocation =
            this.selectedLocation === 'All' ||
            row.Location_g__c === this.selectedLocation;

            // Convert DateTime to Date
        const eventStartDate =
            row.Event_Start_Date_Time__c
                ? row.Event_Start_Date_Time__c.split('T')[0]
                : null;

        const eventEndDate =
            row.Event_End_Date_Time__c
                ? row.Event_End_Date_Time__c.split('T')[0]
                : null;

        const matchesStartDate =
            !this.selectedStartDate ||
            (eventStartDate &&
             eventStartDate >= this.selectedStartDate);

        const matchesEndDate =
            !this.selectedEndDate ||
            (eventEndDate &&
             eventEndDate <= this.selectedEndDate);

        return matchesSearch && matchesLocation && matchesStartDate
            && matchesEndDate;
    });
}
handleBulkSync() {
    window.open(
        '/lightning/flow/Bulk_Billing_Sync_Flow',
        '_blank'
    );
}

async handleRefresh() {

    this.isLoading = true;

    try {

        await refreshApex(this.wiredResult);

    } catch(error) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: 'Unable to refresh records.',
                variant: 'error'
            })
        );

    } finally {

        this.isLoading = false;
    }
}
startPolling() {

    this.pollingInterval = setInterval(async () => {

        try {

            const status = await getBatchStatus({
                jobId: this.batchJobId
            });

            console.log('Batch Status : ' + status);

            if (
                status === 'Completed' ||
                status === 'Failed' ||
                status === 'Aborted'
            ) {

                clearInterval(this.pollingInterval);

                this.isJobRunning = false;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Synchronization Completed',
                        message: 'Billing synchronization has completed successfully. Click Refresh to see the latest status.',
                        variant: 'success'
                    })
                );

            }

        } catch(error){

            console.error(error);

            clearInterval(this.pollingInterval);

            this.isJobRunning = false;
        }

    },5000);

}
disconnectedCallback(){

    if(this.pollingInterval){

        clearInterval(this.pollingInterval);

    }

}
}