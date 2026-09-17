import { LightningElement, api, wire } from 'lwc';
import isAccountDeactivated from '@salesforce/apex/WellSpringAccountDeactivationController.isAccountDeactivated';

export default class WellSpringAccountDeactivationBanner extends LightningElement {
    @api recordId;

    isDeactivated = false;

    // Apex wire is the authoritative deactivation check — avoids FLS gaps
    // that can make getFieldValue silently return null for Is_Deactivated__c.
    @wire(isAccountDeactivated, { accountId: '$recordId' })
    wiredDeactivationStatus({ data, error }) {
        if (data != null) {
            this.isDeactivated = data;
        } else if (error) {
            this.isDeactivated = false;
        }
    }
}