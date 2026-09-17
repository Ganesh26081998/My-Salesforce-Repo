import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getAvailableFields from '@salesforce/apex/MedicationController.getAvailableFields';
import saveSelectedFields from '@salesforce/apex/MedicationController.saveSelectedFields';
import getMedicationData from '@salesforce/apex/MedicationController.getMedicationData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const columns = [    
    {
        label: 'Medication Name',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: {fieldName: 'medicationName'},
            tooltip: { fieldName: 'medicationName' },
            target: '_self'
        },                                        
        sortable: true,
        wrapText: true
    }
];

export default class MedicationsTable extends NavigationMixin(LightningElement) {
    @api recordId;
    columns = columns;
    @track medications = [];
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';
    @track showFieldModal = false;
    @track fieldOptions = [];
    @track selectedFields = [];
    @track limitExceeded = false;
    _lastColumnSignature = '';

    refreshInterval;

    sortedBy             = 'CreatedDate';
    sortDirection        = 'desc';

    connectedCallback() {
        this._isInitialized = true;
        this.loadFieldOptions();
        this.loadData();        
    }

    disconnectedCallback() {

    if(this.refreshInterval) {
        clearInterval(this.refreshInterval);
    }
}
    

    loadData() {

            let sortField = this.sortedBy;

    if (sortField === 'recordUrl') {
        sortField = 'Medication_Name__c';
    } else if (sortField && sortField.includes('.')) {
        sortField = sortField.split('.')[1];
    }

    getMedicationData({   
        accountId: this.recordId,
        sortBy: sortField,
        sortDir: this.sortDirection 
    })
        .then(result => {
            console.log('result: ',result);
             if(!this.showFieldModal) {

                this.selectedFields = result.selectedFields.map(
                    field => field.value
                );
            }
            console.log('this.selectedFields: ',JSON.stringify(this.selectedFields));

            const signature = result.selectedFields.map(f => f.value).join(',');
            if (signature !== this._lastColumnSignature) {
                this._lastColumnSignature = signature;
            
                const dynamicColumns = result.selectedFields.map(field => ({
                        label: field.label,
                        fieldName: field.value,
                        type: 'text',
                        wrapText: true,
                        sortable: true
                    }));

                this.columns = [
                    
                    {
                        label: 'Medication Name',
                        fieldName: 'recordUrl',
                        type: 'url',
                        typeAttributes: {
                            label: {fieldName: 'medicationName'},
                            tooltip: { fieldName: 'medicationName' },
                            target: '_self'
                        },                                        
                        sortable: true,
                        wrapText: true
                    },
                    ...dynamicColumns                               
                ];
            }
            this.medications = result.records.map(row => ({
                id: row.Id,
                recordUrl: `/lightning/r/MedicationStatement/${row.Id}/view`,
                medicationName: row.Medication_Name__c,
                ...row
            }));

            this.isLoading = false;
        })
        .catch(error => {

            this.hasError = true;

            this.errorMessage =
                error?.body?.message || 'Error loading medications';

            this.isLoading = false;
        });
}

    // Safe value extractor for LDS field wrappers
    _val(fieldWrapper) {
        return fieldWrapper ? fieldWrapper.value : null;
    }

    get hasMedications() {
        return this.medications && this.medications.length > 0;
    }

    // showTable: only when not loading and no error
    get showTable() {
        return !this.isLoading && !this.hasError && this.medications &&
           this.medications.length > 0;
    }

    get showNoData() {
        return !this.isLoading &&
            !this.hasError &&
            (!this.medications || this.medications.length === 0);
    }

    // Navigate to MedicationStatement record using NavigationMixin (SPA-friendly)
    handleNavigate(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                actionName: 'view'
            }
        });
    }

    handlePrint() {
        let sortField = this.sortedBy;

        // Medication Name column
        if (sortField === 'recordUrl') {
            sortField = 'Medication_Name__c';
        }
        // Dynamic columns
        else if (sortField && sortField.includes('.')) {
            sortField = sortField.split('.')[1];
        }

        window.open(
            `/apex/MedicationPrintPage?recordId=${this.recordId}` +
            `&sortBy=${sortField}` +
            `&sortDir=${this.sortDirection}`,
            '_blank'
        );
    }

    loadFieldOptions() {

    getAvailableFields()
        .then(result => {
            this.fieldOptions = result;
        })
         .catch(error => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error Loading Fields',
                    message: error?.body?.message || 'Could not load available fields.',
                    variant: 'error'
                })
            );
        });
}

    
    //handle sort
    handleSort(event) {
    const { fieldName, sortDirection } = event.detail;

    this.sortedBy = fieldName;
    this.sortDirection = sortDirection;
    this.isLoading = true;
    this.loadData();

    // const actualFieldName =
    //     fieldName === 'recordUrl'
    //         ? 'medicationName'
    //         : fieldName;

    // const sortedData = [...this.medications];

    // sortedData.sort((a, b) => {
    //     let valueA = a[actualFieldName] ?? '';
    //     let valueB = b[actualFieldName] ?? '';

    //     valueA = valueA.toString().toLowerCase();
    //     valueB = valueB.toString().toLowerCase();

    //     return sortDirection === 'asc'
    //         ? valueA.localeCompare(valueB)
    //         : valueB.localeCompare(valueA);
    // });

    // this.medications = sortedData;
    }

openFieldModal() {
    if(this.refreshInterval) {
        clearInterval(this.refreshInterval);
        this.refreshInterval = null;
    }
    this.showFieldModal = true;
}

closeFieldModal() {
    this.showFieldModal = false;
    // this.startRefresh(); 
}


handleFieldChange(event) {
     const chosen = event.detail.value;

    if(chosen.length > 6) {
        this.limitExceeded = true;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Limit Reached',
                message: 'You can select a maximum of 6 fields.',
                variant: 'error',
                mode: 'dismissable'
            })
        );
        // revert — don't update selectedFields so the 8th is rejected
        return;
    }
    this.limitExceeded = false;
    this.selectedFields = chosen;
}




saveFields() {
    console.log('saveFields called');
    console.log('this.selectedFields.length',this.selectedFields.length);

    if (this.limitExceeded) {    
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Validation Error',
                message: 'You can select a maximum of 6 fields.',
                variant: 'error'
            })
        );
        return;
    }

    saveSelectedFields({ selectedFields: this.selectedFields, accountId: this.recordId })
        .then(() => {
            this.showFieldModal = false;
            // this.startRefresh(); 
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Fields saved successfully.',
                    variant: 'success'
                })
            );
            this.loadData();
        })
        .catch(error => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save Failed',
                    message: error?.body?.message || 'An error occurred while saving fields.',
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        });
}
handleRefresh() {

    this.isLoading = true;

    this.loadData();
}
}