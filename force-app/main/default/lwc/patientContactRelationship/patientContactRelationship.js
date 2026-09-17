import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRelatedContacts from '@salesforce/apex/PatientContactRelationshipController.getRelatedContacts';
import deleteContactRelationship from '@salesforce/apex/PatientContactRelationshipController.deleteContactRelationship';
import { getRecord } from 'lightning/uiRecordApi';
import IS_DEACTIVATED_FIELD from '@salesforce/schema/Account.Is_Deactivated__c';
import LightningConfirm from 'lightning/confirm';
import PatientContactRelationshipModal from 'c/patientContactRelationshipModal';
import PatientContactRelationshipEditModal from 'c/patientContactRelationshipEditModal';

import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
const COLUMNS = [
    {
        label: 'Contact Name',
        fieldName: 'recordUrl',
        type: 'url',
        sortable: true,
        typeAttributes: {
            label: { fieldName: 'recordName' },
            tooltip: { fieldName: 'recordName' },
            target: '_self'
        },
        cellAttributes: { iconName: { fieldName: 'recordIcon' } }
    },
    { label: 'Type',              fieldName: 'type',             sortable: true },
    { label: 'Relationship',      fieldName: 'relationship',     sortable: true },
    { label: 'Additional Duties', fieldName: 'additionalDuties', sortable: true ,wrapText: true},
    {
        label: 'Created Date',
        fieldName: 'createdDate',
        type: 'date',
        sortable: true,
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit'
        }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit',   name: 'edit'   },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

export default class PatientContactRelationship extends LightningElement {

    @api recordId;
    @track contacts      = [];
    @track isLoading     = false;
    columns              = COLUMNS;
    sortedBy             = 'createdDate';
    sortDirection        = 'desc';

    wiredContactsResult;
    @track isDeactivated = false;

    
    @track currentPage = 1;
    pageSize = 10;

    connectedCallback() {
        console.log('PatientContactRelationship recordId:', this.recordId);
        if (this.recordId) {
            this.isLoading = true;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: [IS_DEACTIVATED_FIELD] })
    wiredAccount({ data, error }) {
        if (data) {
            this.isDeactivated = data.fields.Is_Deactivated__c.value;
        } else if (error) {
            console.error('Error fetching account:', error);
        }
    }

    get showAddRelationshipButton() {
        return !this.isDeactivated;
    }

    @wire(getRelatedContacts, { accountId: '$recordId' })
    wiredContacts(result) {
        this.wiredContactsResult = result;
        console.log('wiredContacts result:', result);

        if (result.data) {
            this.contacts = result.data.map(record => {
                const relationshipId   = record.Id;
                const contactIdToOpen  = record.HealthCloudGA__Contact__c;
                const roleName         = record.HealthCloudGA__Role__r?.Name || '—';
                const otherRelationshipValue = record.Other_Relationship_to_Client__c?.trim();

                const relationshipDisplay =
                    roleName === 'Other' && otherRelationshipValue
                        ? `${roleName} - ${otherRelationshipValue}`
                        : roleName;

                return {
                    Id                      : relationshipId,
                    recordName              : record.HealthCloudGA__Contact__r?.Name,
                    recordUrl               : contactIdToOpen
                                                ? `/lightning/r/Contact/${contactIdToOpen}/view`
                                                : null,
                    type                    : record.Type__c,
                    relationship            : relationshipDisplay,
                    additionalDuties        : record.HealthCloudGA__Contact__r?.Additional_duties__c ?
                    record.HealthCloudGA__Contact__r.Additional_duties__c.split(';').join('\n')
                    : '—',
                    phone                   : record.HealthCloudGA__Contact__r?.Phone  || '—',
                    email                   : record.HealthCloudGA__Contact__r?.Email  || '—',
                    createdDate             : record.CreatedDate,

                    
                    contactId               : contactIdToOpen,
                    roleId                  : record.HealthCloudGA__Role__c,
                    relationshipToClient    : record.Relationship_to_Client__c    || '',
                    familyRelationship      : record.Family_Relationship__c       || '',
                    otherRelationshipToClient: record.Other_Relationship_to_Client__c || '',
                    businessType            : record.HealthCloudGA__Contact__r?.Type__c || '',
                    isReferral              : record.Is_Referral__c ===true
                };
            });

            this.sortContacts(
                this.sortedBy === 'recordUrl' ? 'recordName' : this.sortedBy,
                this.sortDirection
            );

            this.currentPage = 1;
            this.isLoading   = false;
        } else if (result.error) {
            console.error('Error loading contacts:', result.error);
            this.showToast('Error', 'Error loading related contacts', 'error');
            this.isLoading = false;
        }
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy       = fieldName;
        this.sortDirection  = sortDirection;
        const actualFieldName = fieldName === 'recordUrl' ? 'recordName' : fieldName;
        this.sortContacts(actualFieldName, sortDirection);
    }

    sortContacts(fieldName, sortDirection) {
        const sortedData = [...(this.contacts || [])];
        sortedData.sort((a, b) => {
            let valueA = a[fieldName];
            let valueB = b[fieldName];

            if (fieldName === 'createdDate') {
                valueA = valueA ? new Date(valueA).getTime() : 0;
                valueB = valueB ? new Date(valueB).getTime() : 0;
            } else {
                valueA = (valueA ?? '').toString().trim().toLowerCase();
                valueB = (valueB ?? '').toString().trim().toLowerCase();
            }

            if (valueA === valueB) return 0;
            const compareResult = valueA > valueB ? 1 : -1;
            return sortDirection === 'asc' ? compareResult : -compareResult;
        });
        this.contacts = sortedData;
    }

    get hasContacts() {
        return this.contacts && this.contacts.length > 0;
    }

    
    get totalRecords() { return this.contacts?.length || 0; }
    get totalPages()   { return Math.max(1, Math.ceil(this.totalRecords / this.pageSize)); }
    get pagedContacts() {
        const start = (this.currentPage - 1) * this.pageSize;
        return (this.contacts || []).slice(start, start + this.pageSize);
    }
    get isPrevDisabled() { return this.currentPage <= 1; }
    get isNextDisabled() { return this.currentPage >= this.totalPages; }
    get startRecord() {
        if (!this.totalRecords) return 0;
        return (this.currentPage - 1) * this.pageSize + 1;
    }
    get endRecord() {
        if (!this.totalRecords) return 0;
        return Math.min(this.currentPage * this.pageSize, this.totalRecords);
    }

    handlePrev() { if (this.currentPage > 1) this.currentPage -= 1; }
    handleNext() { if (this.currentPage < this.totalPages) this.currentPage += 1; }

    
    async handleAddRelationship() {
        const result = await PatientContactRelationshipModal.open({
            recordId: this.recordId
        });
        if (result === 'saved') {
            await refreshApex(this.wiredContactsResult);
        }
    }

    handleMenuSelect(event) {
        if (event.detail.value === 'add_relationship') {
            this.handleAddRelationship();
        }
    }

    
    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row        = event.detail.row;

        if (actionName === 'edit') {
            await this.handleEditRow(row);
        } else if (actionName === 'delete') {
            await this.handleDeleteRow(row);
        }
    }

    async handleEditRow(row) {
        const result = await PatientContactRelationshipEditModal.open({
            
            relationshipId           : row.Id,
            contactId                : row.contactId,
            contactName              : row.recordName,
            ccrType                  : row.type,
            relatedAccountId         : this.recordId,

            
            roleId                   : row.roleId,
            relationshipToClientInit : row.relationshipToClient,
            familyRelationshipInit   : row.familyRelationship,
            otherRelationshipToClientInit: row.otherRelationshipToClient,

            
            businessTypeInit         : row.businessType,
            isReferralInit           : row.isReferral
        });

        if (result === 'saved') {
            await refreshApex(this.wiredContactsResult);

            notifyRecordUpdateAvailable([{ recordId: row.contactId }]);

            if (this.currentPage > this.totalPages) {
                this.currentPage = this.totalPages;
            }
        }
    }

    async handleDeleteRow(row) {
        const confirmed = await LightningConfirm.open({
            message : 'Are you sure you want to delete this relationship? This action cannot be undone.',
            label   : 'Confirm Delete',
            variant : 'header',
            theme   : 'warning'
        });

        if (confirmed) {
            this.isLoading = true;

            deleteContactRelationship({ relationshipId: row.Id })
                .then(() => {
                    this.showToast('Success', 'Relationship deleted successfully', 'success');
                    return refreshApex(this.wiredContactsResult);
                })
                .then(() => {
                    if (this.currentPage > this.totalPages) {
                        this.currentPage = this.totalPages;
                    }
                })
                .catch(error => {
                    console.error('Error deleting relationship:', error);
                    this.showToast(
                        'Error',
                        error.body?.message || 'Error deleting relationship',
                        'error'
                    );
                })
                .finally(() => {
                    this.isLoading = false;
                });
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}