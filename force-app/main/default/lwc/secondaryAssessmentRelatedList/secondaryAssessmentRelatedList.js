import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getAssessments from '@salesforce/apex/SecondaryAssessmentController.getAssessments';
import {
    subscribe,
    unsubscribe,
    MessageContext,
    APPLICATION_SCOPE
} from 'lightning/messageService';
import SECONDARY_ASSESSMENT_REFRESH_CHANNEL from '@salesforce/messageChannel/secondaryAssessmentRefresh__c';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openSubtab,
    setTabLabel,
    setTabIcon
} from 'lightning/platformWorkspaceApi';
import LightningConfirm from 'lightning/confirm';
import deleteAssessment from '@salesforce/apex/SecondaryAssessmentController.deleteAssessment';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import LOCALE from '@salesforce/i18n/locale';

export default class SecondaryAssessmentRelatedList extends NavigationMixin(LightningElement) {

    @api recordId;
    assessments = [];
    wiredAssessmentResult;
    subscription = null;

    @wire(MessageContext)
    messageContext;

    @wire(IsConsoleNavigation)
    isConsoleNavigation;

    connectedCallback() {
        this.subscribeToMessageChannel();
    }

    subscribeToMessageChannel() {

        if (this.subscription) {
            return;
        }

        this.subscription = subscribe(
            this.messageContext,
            SECONDARY_ASSESSMENT_REFRESH_CHANNEL,
            (message) => this.handleMessage(message),
             {
                scope: APPLICATION_SCOPE
            }
        );
    }

    handleMessage(message) {

        console.log(
            'LMS message received:',
            JSON.stringify(message)
        );

        console.log(
            'Current Account:',
            this.recordId
        );

        if (
            message.accountId === this.recordId &&
            this.wiredAssessmentResult
        ) {
            console.log('Refreshing related list');
            refreshApex(this.wiredAssessmentResult);
        }
    }

    disconnectedCallback() {

        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = null;
        }
    }

    @wire(getAssessments, {
        accountId: '$recordId'
    })
    wiredAssessments(result) {

        this.wiredAssessmentResult = result;
        const { data, error } = result;

        const localizeDateTime = (utcString) => {
                if (!utcString) return '';
                return new Intl.DateTimeFormat(LOCALE, {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    // hour: '2-digit',
                    // minute: '2-digit',
                    //second: '2-digit',
                    hour12: true,
                    timeZone: TIME_ZONE // This forces the conversion to the user's CDT profile setting
                }).format(new Date(utcString));
            };


        if (data) {
             this.assessments = data.map(assessment => ({
                ...assessment,

                displayLabel:
                    `${assessment.Assessment_Type__c} - ` +
                    `${localizeDateTime(assessment.CreatedDate)} - ` +
                    `${assessment.CreatedBy.Name}`
            }));
        }
        else if (error) {
            console.error(error);
        }

    }

    formatDate(dateValue) {

    if (!dateValue) {
        return '';
    }

    return new Intl.DateTimeFormat('en-US', {
        month: '2-digit',
        day: '2-digit',
        year: 'numeric'
    }).format(new Date(dateValue));
}

    get cardTitle(){
        const count = this.assessments.length;
        return `Secondary Assessments (${count > 3 ? '3+' : count})`;
    }

    get displayedAssessments() {
        return this.assessments.slice(0, 3);
    }

    get hasMoreAssessments() {
        return this.assessments.length > 3;
    }

    async handleNew() {

    try {

        const focusedTab =
            await getFocusedTabInfo();

        const parentTabId =
            focusedTab.isSubtab
                ? focusedTab.parentTabId
                : focusedTab.tabId;

        const newSubtabId = await openSubtab(
            parentTabId,
            {
                pageReference: {
                    type: 'standard__component',
                    attributes: {
                        componentName:
                            'c__secondaryAssessmentCreate'
                    },
                    state: {
                        c__recordId: this.recordId
                    }
                },
                focus: true
            }
        );

        console.log('newSubtabId : ',newSubtabId);

        await setTabLabel(
            newSubtabId,
            'New Secondary Assessment'
        );

        await setTabIcon(
            newSubtabId,
            'custom:custom27',
            {
                iconAlt: 'Secondary Assessment'
            }
        );

    } catch (error) {

        console.error(
            'Open Create Subtab Error:',
            error
        );

        console.error(
            'Error Message:',
            error?.message
        );

        console.error(
            'Error Stack:',
            error?.stack
        );
    }
}

    handleRecordClick(event) {

        event.preventDefault();

        const assessmentId =
            event.currentTarget.dataset.id;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: assessmentId,
                objectApiName: 'SecondaryAssessment__c',
                actionName: 'view'
            }
        });
    }

    handleMenuSelect(event) {

        const selectedAction = event.detail.value;

        if (selectedAction === 'new') {
            this.handleNew();
        }
    }

    handleViewAll(event) {
        event.preventDefault();

        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Account',
                relationshipApiName: 'Secondary_Assessments__r',
                actionName: 'view'
            }
        });
    }

    async handleRowAction(event) {

    const assessmentId =
        event.currentTarget.dataset.id;

    const action =
        event.detail.value;

    if (action === 'edit') {

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: assessmentId,
                objectApiName: 'SecondaryAssessment__c',
                actionName: 'edit'
            }
        });

        return;
    }

    if (action === 'delete') {

    const confirmed = await LightningConfirm.open({
        message:
            'Are you sure you want to delete this Secondary Assessment?',
        label: 'Delete Secondary Assessment',
        theme: 'warning'
    });

    if (!confirmed) {
        return;
    }

    try {

        await deleteAssessment({
            assessmentId
        });

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Secondary Assessment deleted successfully.',
                variant: 'success'
            })
        );

        await refreshApex(
            this.wiredAssessmentResult
        );

    } catch (error) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message:
                    error.body?.message ||
                    'Unable to delete the Secondary Assessment.',
                variant: 'error'
            })
        );
    }
}
}

}