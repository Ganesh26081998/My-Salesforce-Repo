import { LightningElement, api, wire } from 'lwc';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

export default class BusinessAccountWarning extends LightningElement {
    @api recordId;
    showWarning = false;
    warningMessage = 'Contact not created for this business.';

    wiredContactsResult;

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Contacts',
        fields: ['Contact.Id']
    })
    wiredContacts(result) {
        this.wiredContactsResult = result;

        if (result.data) {
            const contactCount = result.data.records.length;
            this.showWarning = contactCount === 0;
        } 
        else if (result.error) {
            console.error('Error fetching contacts', result.error);
        }
    }
}