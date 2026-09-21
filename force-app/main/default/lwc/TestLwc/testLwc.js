import { LightningElement } from 'lwc';

export default class TestLwc extends LightningElement {
    connectedCallback() {
        console.log('testLwc component loaded');
    }
}