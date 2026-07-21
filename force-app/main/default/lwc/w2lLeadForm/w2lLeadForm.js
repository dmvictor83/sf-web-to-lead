import { LightningElement, track } from 'lwc';
import submitLead from '@salesforce/apex/W2LController.submitLead';
import CAPTCHA_IFRAME from '@salesforce/resourceUrl/w2lCaptcha';

const STATES = [
    'Alabama','Alaska','Arizona','Arkansas','California','Colorado','Connecticut',
    'Delaware','District of Columbia','Florida','Georgia','Hawaii','Idaho','Illinois',
    'Indiana','Iowa','Kansas','Kentucky','Louisiana','Maine','Maryland','Massachusetts',
    'Michigan','Minnesota','Mississippi','Missouri','Montana','Nebraska','Nevada',
    'New Hampshire','New Jersey','New Mexico','New York','North Carolina','North Dakota',
    'Ohio','Oklahoma','Oregon','Pennsylvania','Rhode Island','South Carolina',
    'South Dakota','Tennessee','Texas','Utah','Vermont','Virginia','Washington',
    'West Virginia','Wisconsin','Wyoming'
];
const COUNTRIES = ['United States','Canada','United Kingdom','Australia','Ireland','Mexico'];

export default class W2lLeadForm extends LightningElement {
    states = STATES;
    countries = COUNTRIES;
    captchaUrl = CAPTCHA_IFRAME + '?v=6';

    @track form = {
        firstName: '', lastName: '', company: '', email: '', phone: '',
        website: '', street: '', city: '', state: '', postalCode: '',
        country: 'United States'
    };

    errorMessage = '';
    submitting = false;
    showForm = true;
    showSuccess = false;
    showLimit = false;

    _captchaToken = '';
    _messageHandler;
    // Fixed height that always fits the reCAPTCHA image challenge. LWS blocks
    // the iframe->parent resize handshake on guest LWR sites, so we can't shrink
    // it dynamically — a generous fixed height guarantees the grid is visible.
    captchaHeight = 610;

    get submitLabel() {
        return this.submitting ? 'Sending…' : 'Send message';
    }

    get captchaStyle() {
        return `width:100%;max-width:410px;height:${this.captchaHeight}px;border:0;`;
    }

    connectedCallback() {
        this._messageHandler = (event) => {
            const data = event && event.data;
            if (data && data.w2l === 'captcha') {
                this._captchaToken = data.token || '';
            }
        };
        window.addEventListener('message', this._messageHandler);
    }

    disconnectedCallback() {
        if (this._messageHandler) {
            window.removeEventListener('message', this._messageHandler);
        }
    }

    handleInput(event) {
        this.form[event.target.dataset.field] = event.target.value;
    }

    async handleSubmit() {
        this.errorMessage = '';
        if (!this._captchaToken) {
            this.errorMessage = 'Please complete the reCAPTCHA checkbox.';
            return;
        }

        this.submitting = true;
        try {
            const payload = { ...this.form, captchaToken: this._captchaToken };
            const result = await submitLead({ payloadJson: JSON.stringify(payload) });

            if (result.statusCode === 429) {
                this.showForm = false;
                this.showLimit = true;
            } else if (result.success) {
                this.showForm = false;
                this.showSuccess = true;
            } else {
                this.errorMessage = result.message || 'Something went wrong. Please try again.';
                this._captchaToken = '';
            }
        } catch (e) {
            this.errorMessage = 'Network error. Please try again.';
            this._captchaToken = '';
        } finally {
            this.submitting = false;
        }
    }
}
