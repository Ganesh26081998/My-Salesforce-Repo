import { LightningElement, track, wire } from 'lwc';
import createAccount from '@salesforce/apex/WellSpringFormController.createAccount';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import LeadRTId from '@salesforce/label/c.Prospect_RT_DeveloperName';
import STATE_FIELD from '@salesforce/schema/Account.State__c';
import I_AM_FIELD from '@salesforce/schema/Account.I_am__c';
import RELATIONSHIP_FIELD from '@salesforce/schema/Account.Your_Relationship__c';
import HEARD_ABOUT_US_FIELD from '@salesforce/schema/Account.How_did_you_hear_about_us__c';
import Toast from 'lightning/toast';

export default class WellSpringForm extends LightningElement {

    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track street = '';
    @track city = '';
    @track state = '';
    @track zip = '';
    @track iAm = '';
    @track otherIAm = ''; // NEW: For "Other" option in I am dropdown
    @track otherRelationship = '';
    @track heardAboutUs = '';
    @track otherHeardAboutUs = ''; // NEW: For "Other" option details
    @track message = '';
    @track showThankYou = false;
    @track isSubmitting = false; // NEW: Track loading state

    recordTypeId = LeadRTId;

    stateOptions = [];
    iAmOptions = [];
    allRelationshipOptions = []; // Store all relationship options
    otherOptions = []; // Filtered relationship options
    heardOptions = [];

    // Mapping of "I am" values to relationship field values
    // Updated to match actual Salesforce picklist values from Your_Relationship__c field
    relationshipMapping = {
        'Senior or Family Member': ['Mother', 'Father', 'Son', 'Daughter', 'Sister', 'Sibling', 'Brother', 'Grandson', 'Granddaughter', 'Grandmother', 'Grandfather', 'Aunt', 'Uncle', 'Niece', 'Nephew', 'Cousin', 'Self', 'Other relative', 'Friend/Neighbor', 'Daughter-in-Law', 'Son-in-Law'],
        'Healthcare Partner': ['Mother', 'Father', 'Son', 'Daughter', 'Sister', 'Sibling', 'Brother', 'Grandson', 'Granddaughter', 'Grandmother', 'Grandfather', 'Aunt', 'Uncle', 'Niece', 'Nephew', 'Cousin', 'Self', 'Other relative', 'Friend/Neighbor', 'Daughter-in-Law', 'Son-in-Law', 'Caregiver', 'Social Worker/Case Manager']
    };

    // ============== PICKLIST WIRES ==============

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: STATE_FIELD })
    wiredState({ data }) {
        if (data) {
            this.stateOptions = data.values;
        }
    }

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: I_AM_FIELD })
    wiredIam({ data }) {
        if (data) {
            this.iAmOptions = data.values;
        }
    }

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: RELATIONSHIP_FIELD })
    wiredRelationship({ data }) {
        if (data) {
            // Store ALL relationship options
            this.allRelationshipOptions = data.values;
            // Initially show all options
            this.otherOptions = data.values;
        }
    }

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: HEARD_ABOUT_US_FIELD })
    wiredHeard({ data }) {
        if (data) {
            this.heardOptions = data.values;
        }
    }

    // ============== HANDLE CHANGE ==============

    handleChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.value;

        // When "I am" field changes, filter the relationship options
        if (field === 'iAm') {
            this.filterRelationshipOptions(event.target.value);
        }

        if (field === 'email') {
            event.target.setCustomValidity('');
            event.target.reportValidity();
        }
    }

    // ============== FILTER RELATIONSHIP OPTIONS ==============

    filterRelationshipOptions(iAmValue) {
        // If "Other" is selected, clear relationship fields
        if (iAmValue === 'Other') {
            this.otherOptions = [];
            this.otherRelationship = '';
            this.otherIAm = '';
            return;
        }

        if (!iAmValue || !this.allRelationshipOptions || this.allRelationshipOptions.length === 0) {
            this.otherOptions = [];
            this.otherRelationship = ''; // Clear selected relationship
            this.otherIAm = ''; // Clear "Other" details
            return;
        }

        // Get the filtered labels from mapping
        const allowedLabels = this.relationshipMapping[iAmValue];

        if (!allowedLabels) {
            // If no mapping exists, show all options (fallback)
            this.otherOptions = this.allRelationshipOptions;
        } else {
            // Filter the options based on allowed labels
            this.otherOptions = this.allRelationshipOptions.filter(option => 
                allowedLabels.includes(option.label)
            );
        }

        // Reset the selected relationship when "I am" changes
        this.otherRelationship = '';
        this.otherIAm = ''; // Clear "Other" details
    }

    // ============== GETTER: Check if "Other" selected in heardAboutUs ==============

    get showOtherHeardAboutUsField() {
        return this.heardAboutUs === 'Other';
    }

    // ============== GETTER: Check if "Other" selected in I am ==============

    get showOtherIAmField() {
        return this.iAm === 'Other';
    }

    // ============== GETTER: Check if should show relationship dropdown ==============

    get showRelationshipDropdown() {
        return this.iAm && this.iAm !== 'Other';
    }

    // ============== HANDLE SUBMIT ==============

    handleSubmit() {
        const fields = this.template.querySelectorAll(
            'lightning-input, lightning-combobox, lightning-textarea'
        );

        let valid = true;
        fields.forEach(field => {
            if (!field.reportValidity()) {
                valid = false;
            }
        });

        if (!valid) return;

        // Set loading state
        this.isSubmitting = true;

        createAccount({
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            street: this.street,
            city: this.city,
            state: this.state,
            zip: this.zip,
            iAm: this.iAm,
            otherIAm: this.otherIAm,
            otherRelationship: this.otherRelationship,
            heardAboutUs: this.heardAboutUs,
            otherHeardAboutUs: this.otherHeardAboutUs,
            message: this.message
        })
        .then((accountId) => {
            // accountId is returned from Apex
            console.log('Account created successfully with ID: ' + accountId);

            // Clear old email validation
            const emailInput = this.template.querySelector(
                'lightning-input[data-field="email"]'
            );
            if (emailInput) {
                emailInput.setCustomValidity('');
                emailInput.reportValidity();
            }

            this.showThankYou = true;

            // Success toast (auto-dismiss)
            this.showToast('Success', 'Thanks for your interest', 'success');
        })
        .catch(error => {
            console.error(JSON.stringify(error));

            let messages = [];

            if (error?.body?.pageErrors?.length) {
                messages = error.body.pageErrors.map(e => e.message);
            }
            else if (error?.body?.fieldErrors) {
                Object.values(error.body.fieldErrors).forEach(fieldErrArray => {
                    fieldErrArray.forEach(err => messages.push(err.message));
                });
            }
            else if (error?.body?.message) {
                messages.push(error.body.message);
            }
            else {
                messages.push('An unexpected error occurred.');
            }

            const finalMessage = messages.join('\n');

            // Error toast (auto-dismiss)
            this.showToast('Error', finalMessage, 'error');

            const emailInput = this.template.querySelector(
                'lightning-input[data-field="email"]'
            );
            if (emailInput) {
                emailInput.setCustomValidity(finalMessage);
                emailInput.reportValidity();
            }
        })
        .finally(() => {
            // Reset loading state whether success or error
            this.isSubmitting = false;
        });
    }

    // ============== TOAST ==============

    showToast(title, message, variant) {
        Toast.show({
            label: title,
            message,
            variant,
            mode: 'dismissible' // auto-dismiss for ALL toasts
        });
    }
}