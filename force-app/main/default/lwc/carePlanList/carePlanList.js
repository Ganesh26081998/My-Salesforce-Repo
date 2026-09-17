import { LightningElement, wire, api, track } from 'lwc';
import getCarePlans from '@salesforce/apex/CarePlanCaseController.getCarePlans';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { getFocusedTabInfo, openSubtab } from 'lightning/platformWorkspaceApi';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getNextCarePlanTitle from '@salesforce/apex/CarePlanCaseController.getNextCarePlanTitle';
import { CurrentPageReference } from 'lightning/navigation';
import { subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import CARE_PLAN_REFRESH_CHANNEL from '@salesforce/messageChannel/CarePlanRefreshChannel__c';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import IS_DEACTIVATED_FIELD from '@salesforce/schema/Account.Is_Deactivated__c';
import getLatestCarePlanPdfBase64 from '@salesforce/apex/CarePlanCaseController.getLatestCarePlanPdfBase64';


const COLUMNS = [
    {
        label: 'Care Plan Name',
        fieldName: 'carePlanUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'Subject' },
            tooltip: { fieldName: 'Subject' },
            target: '_self'
        }
    },
    {
        label: 'Created By',
        fieldName: 'createdByName',
        type: 'text'
    },
    {
        label: 'Created Date',
        fieldName: 'CreatedDate',
        type: 'date'
    },
    {
        label: 'Last Modified By',
        fieldName: 'lastModifiedByName',
        type: 'text'
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Clone', name: 'clone' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

export default class CarePlanList extends NavigationMixin(LightningElement) {

    columns = COLUMNS;
    carePlans = [];
    wiredResult;
    refreshHandlerId;
    @api recordId;
    showDeleteModal = false;
    recordToDelete;
    showNewModal = false;
    showEditModal = false;
    selectedRecordId;
    selectedRecordTitle = '';
    accId;
    @track carePlanTitle = '';
    subscription = null;
    isAccountDeactivated = false;




    // -----------------------------
    // Fetch Care Plans
    // -----------------------------
    @wire(getCarePlans, { accountId: '$recordId' })
    wiredCarePlans(result) {
        this.wiredResult = result;
        console.log('recordId:', this.recordId);
        console.log('wired result:', result);
        if (result.data) {
            this.carePlans = result.data.map(cp => ({
                ...cp,
                createdByName: cp.CreatedBy.Name,
                lastModifiedByName: cp.LastModifiedBy.Name,
                carePlanUrl: `/lightning/n/Edit_Care_Plan?c__carePlanId=${cp.Id}`
            }));
            console.log('carePlans:', this.carePlans);
        } else if (result.error) {
            console.error('Error fetching care plans:', result.error);
        }
    }

    @wire(MessageContext)
        messageContext;

    get displayedCarePlans() {
    return this.carePlans.slice(0, 5);
}

@wire(getRecord, { recordId: '$recordId', fields: [IS_DEACTIVATED_FIELD] })
wiredAccount({ data, error }) {
    if (data) {
        this.isAccountDeactivated = !!getFieldValue(data, IS_DEACTIVATED_FIELD);
    } else if (error) {
        // fallback: keep button visible if account couldn't be read
        this.isAccountDeactivated = false;
        console.error('Error fetching account deactivation flag:', error);
    }
}
get showNewButton() {
    return !this.isAccountDeactivated;
}



   

    async handleNewCarePlan() {
        const tabInfo = await getFocusedTabInfo();
        console.log('Focused Tab Info--', JSON.stringify(tabInfo));

        await openSubtab(tabInfo.tabId, {
            pageReference: {
                type: 'standard__navItemPage',
                attributes: {
                    apiName: 'New_Care_Plan'
                },
                state: {
                    c__recordId: this.recordId,
                    //action name is view but i want to create case record  in this page


                }
            },
            label: 'New Care Plan',
            focus: true
        });

    }

    async handlePreviewLatestCarePlan() {
    try {
        const pdfBase64 = await getLatestCarePlanPdfBase64({ accountId: this.recordId });

        if (!pdfBase64) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Info',
                message: 'No PDF found for the latest Care Plan.',
                variant: 'info'
            }));
            return;
        }

        // Same pattern used in carePlanEdit preview
        const byteCharacters = atob(pdfBase64);
        const byteNumbers = new Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {
            byteNumbers[i] = byteCharacters.charCodeAt(i);
        }

        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], { type: 'application/pdf' });
        const blobUrl = URL.createObjectURL(blob);

        window.open(blobUrl, '_blank');
        setTimeout(() => URL.revokeObjectURL(blobUrl), 60000);
    } catch (error) {
        console.error('Preview error:', JSON.stringify(error));
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: error?.body?.message || error?.message || 'Failed to open latest Care Plan PDF.',
            variant: 'error'
        }));
    }
}


    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef?.state?.recordId) {
            this.recordId = pageRef.state.recordId;
            console.log('Record Id from page reference in:', this.recordId);
            this.loadData();
        }
    }

    loadData() {
        console.log('Record Id ready:', this.recordId);
        this.generateCarePlanTitle();
    }
    get hasCarePlans() {
    return this.carePlans && this.carePlans.length > 0;
}

   

    handleTitleChange(e) {
        this.carePlanTitle = e.detail.value;
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'delete') {
            this.recordToDelete = row.Id;
            if (this.isAccountDeactivated) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Not Allowed',
                        message: 'Account is deactivated. Deleting Care Plan is not allowed.',
                        variant: 'error'
                    })
                );
                return;
            }
            this.showDeleteModal = true;
        }

       

         if (actionName === 'edit') {
        const tabInfo = await getFocusedTabInfo();
            if (this.isAccountDeactivated) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Not Allowed',
                        message: 'Account is deactivated. Editing Care Plan is not allowed.',
                        variant: 'error'
                    })
                );
                return;
            }

        await openSubtab(tabInfo.tabId, {
            pageReference: {
                type: 'standard__navItemPage',
                attributes: {
                    apiName: 'Edit_Care_Plan'
                },
                state: {
                    c__carePlanId: row.Id // 👈 KEY
                }
            },
            label: `Edit Care Plan`,
            focus: true
        });
    }
    if (actionName === 'clone') {
    const tabInfo = await getFocusedTabInfo();
        if (this.isAccountDeactivated) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Not Allowed',
                        message: 'Account is deactivated. Cloning Care Plan is not allowed.',
                        variant: 'error'
                    })
                );
                return;
            }
    await openSubtab(tabInfo.tabId, {
        pageReference: {
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Edit_Care_Plan'
            },
            state: {
                c__carePlanId: row.Id,
                c__mode: 'clone'  // Pass clone mode flag
            }
        },
        label: 'Clone Care Plan',
        focus: true
    });
}

        
    }



   
    async handleViewAll() {
       
        const tabInfo = await getFocusedTabInfo();
        console.log('Focused Tab Info--', JSON.stringify(tabInfo));
        try {
            await openSubtab(tabInfo.tabId, {
                pageReference: {
                    type: 'standard__navItemPage',
                    attributes: {
                        apiName: 'Care_Plan_List'
                    },
                    state: {
                        c__accountId: this.recordId // ⭐ Pass account ID to the App Page
                    }
                },
                focus: true,
                label: 'Care Plans'
            });
        } catch (error) {
            console.error(error);
        }
    }

    closeModal() {
        this.showDeleteModal = false;
        this.recordToDelete = null;
    }

    closeNewModal() {
        this.showNewModal = false;
    }



   
    confirmDelete() {
        deleteRecord(this.recordToDelete)
            .then(() => {
                this.showDeleteModal = false;
                this.recordToDelete = null;

                //  Show success toast
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Care Plan has been deleted successfully!',
                        variant: 'success'
                    })
                );

                return refreshApex(this.wiredResult);
            })
            .catch(error => {
                console.error('Delete failed', error);

                //  Optional error toast
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Failed to delete Care Plan',
                        variant: 'error'
                    })
                );
            });
    }

   
   

    closeEditModal() {
        this.showEditModal = false;
        this.selectedRecordId = null;
    }
    closeNewModal() {
        this.showNewModal = false;
    }


    // -----------------------------
    // Refresh Support
    // -----------------------------
    connectedCallback() { 
          console.log('🟢 CarePlanList Connected');
        console.log('🟢 Message Context:', this.messageContext);
        this.refreshHandlerId = registerRefreshHandler(
            this,
            this.handleRefresh.bind(this)
        );
        this.subscribeToMessageChannel();
        
    }
    
subscribeToMessageChannel() {
    console.log('SUBSCRIBING TO MESSAGE CHANNEL WITH APPLICATION SCOPE');
    
    if (!this.subscription) {
        try {
            this.subscription = subscribe(
                this.messageContext,
                CARE_PLAN_REFRESH_CHANNEL,
                (message) => this.handleMessage(message),
                { scope: APPLICATION_SCOPE }
            );
            console.log('SUBSCRIPTION SUCCESSFUL:', this.subscription);
        } catch (error) {
            console.error('SUBSCRIPTION ERROR:', error);
        }
    }
}



// Handle incoming message
handleMessage(message) {
    console.log('Received refresh message:', message);
    
    if (message.refreshList) {
        // ⭐ Refresh the care plan list
        this.refreshCarePlanList();
    }
}

// Refresh care plan list
refreshCarePlanList() {
    
    console.log('Refreshing care plan list...');
     refreshApex(this.wiredResult)
        .then(() => {
            console.log('Care plan list refreshed successfully');
        })
        .catch(error => {
            console.error('Error refreshing care plan list:', error);
        });
}
 handleRefresh() {
        console.log('🔄 RefreshEvent received - refreshing care plans');
        return refreshApex(this.wiredResult);
    }

    disconnectedCallback() {
        unregisterRefreshHandler(this.refreshHandlerId);
        // ⭐ Unsubscribe from message channel
        if (this.subscription) {
            unsubscribe(this.subscription);
        }
    }

   
}