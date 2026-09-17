import { LightningElement, track, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import BILLING_DATE_FILTER_CHANNEL from '@salesforce/messageChannel/billingDateFilter__c';
import getPendingBillingEvents from '@salesforce/apex/EventBillingController.getPendingBillingEvents';

export default class EventPendingBillingList extends LightningElement {

    @track events = [];
    @track isLoading = false;

    @track startDate;
    @track endDate;

    limitSize = 50;
    offset = 0;
    hasMoreData = true;

    @wire(MessageContext)
    messageContext;

    //  CHANGE: StartDateTime and EndDateTime replaced with StartDateDisplay
    //            and EndDateDisplay (type:'text') to avoid UTC→local timezone
    //            shifting that caused all-day events to show previous date
    columns = [
        {
            label: 'Name',
            fieldName: 'recordUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'Subject' },
                target: '_blank'
            }
        },
        { label: 'Start', fieldName: 'StartDateDisplay', type: 'text' },
        { label: 'End',   fieldName: 'EndDateDisplay',   type: 'text' },
        { label: 'Client Name', fieldName: 'clientName' },
    ];

    connectedCallback() {
        this.loadMoreData();
    }

    handleStartDate(event) {
        this.startDate = event.target.value;
    }

    handleEndDate(event) {
        this.endDate = event.target.value;
    }

    applyFilter() {
        this.events = [];
        this.offset = 0;
        this.hasMoreData = true;

        const message = {
            startDate: this.startDate,
            endDate: this.endDate
        };
        publish(this.messageContext, BILLING_DATE_FILTER_CHANNEL, message);

        this.loadMoreData();
    }

    //  CHANGE: New helper method added
    //    - All-day events (IsAllDayEvent=true): slices date directly from ISO
    //      string "YYYY-MM-DD" without creating a Date object, so no timezone
    //      conversion happens — fixes the "previous date" bug
    //    - Timed events (IsAllDayEvent=false): uses normal Date conversion,
    //      existing behavior unchanged
    formatDate(dateVal, isAllDay) {
        if (!dateVal) return '';

        if (isAllDay) {
            // Slice "YYYY-MM-DD" directly — no Date object, no timezone shift
            const [year, month, day] = dateVal.substring(0, 10).split('-');
            return `${month}/${day}/${year}`;
        }

        return new Date(dateVal).toLocaleDateString('en-US', {
            year:  'numeric',
            month: '2-digit',
            day:   '2-digit'
        });
    }

    loadMoreData() {
        if (!this.hasMoreData) return;

        this.isLoading = true;

        getPendingBillingEvents({
            limitSize: this.limitSize,
            offsetVal: this.offset,
            startDate: this.startDate,
            endDate: this.endDate
        })
        .then(result => {
    if (result.length < this.limitSize) {
        this.hasMoreData = false;
    }

    const mappedRecords = result.map(row => ({
    ...row,
    recordUrl: '/' + row.Id,
    clientName: row.Who ? row.Who.Name : '', // CHANGE: Only Who.Name since all results are now person accounts

    StartDateDisplay: this.formatDate(row.StartDateTime, row.IsAllDayEvent),
    EndDateDisplay:   this.formatDate(row.EndDateTime,   row.IsAllDayEvent)
}));

const updatedRecords = mappedRecords.filter(function(row) {
    return row.clientName;
});

this.events = [...this.events, ...updatedRecords];
this.offset += this.limitSize;
this.isLoading = false;
})
        .catch(error => {
            console.error(error);
            this.isLoading = false;
        });
    }
}