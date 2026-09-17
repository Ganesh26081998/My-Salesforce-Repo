import { LightningElement, api } from 'lwc';
import ADD_MEDICATION_LABEL from '@salesforce/label/c.ADD_MEDICATION_LABEL';
import { NavigationMixin } from 'lightning/navigation';

import { encodeDefaultFieldValues }
    from 'lightning/pageReferenceUtils';

export default class MedicationNewButton
    extends NavigationMixin(LightningElement) {

    @api recordId;
    label = ADD_MEDICATION_LABEL;

    handleNewMedication() {

        const defaultValues =
            encodeDefaultFieldValues({
                PatientId: this.recordId
            });

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'MedicationStatement',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: defaultValues
            }
        });
    }
}