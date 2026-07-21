@RestResource(urlMapping='/w2l/*')
global without sharing class W2LController {

    private static final Integer DEFAULT_MONTHLY_LIMIT = 1000;
    private static final String  RECAPTCHA_VERIFY_URL  =
        'https://www.google.com/recaptcha/api/siteverify';
    private static final String  ALLOWED_ORIGIN        =
        'https://dmvictor83.github.io';

    // ─── Shared result shape ────────────────────────────────────────────────

    global class SubmitResult {
        @AuraEnabled global Integer statusCode;
        @AuraEnabled global Boolean success;
        @AuraEnabled global String  message;
        SubmitResult(Integer c, Boolean s, String m) {
            statusCode = c; success = s; message = m;
        }
    }

    // ─── REST entry point: POST /services/apexrest/w2l/ ──────────────────────
    // Used by the external GitHub Pages form (cross-origin).

    @HttpPost
    global static void handlePost() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        res.addHeader('Access-Control-Allow-Origin',  ALLOWED_ORIGIN);
        res.addHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
        res.addHeader('Access-Control-Allow-Headers', 'Content-Type');

        SubmitResult r;
        try {
            Map<String, Object> body = (Map<String, Object>)
                JSON.deserializeUntyped(RestContext.request.requestBody.toString());
            r = process(body);
        } catch (Exception e) {
            r = new SubmitResult(500, false,
                'An unexpected error occurred. Please try again.');
        }
        res.statusCode   = r.statusCode;
        res.responseBody = Blob.valueOf(
            '{"success":' + r.success + ',"message":' +
            JSON.serialize(r.message) + '}');
    }

    // ─── Aura/LWC entry point ────────────────────────────────────────────────
    // Used by the in-site Experience Cloud page (same-origin, no CORS).

    @AuraEnabled
    global static SubmitResult submitLead(String payloadJson) {
        try {
            Map<String, Object> body = (Map<String, Object>)
                JSON.deserializeUntyped(payloadJson);
            return process(body);
        } catch (Exception e) {
            return new SubmitResult(500, false,
                'An unexpected error occurred. Please try again.');
        }
    }

    // Site key is public (it appears in client HTML) — safe to expose to the LWC.
    @AuraEnabled(cacheable=true)
    global static String getSiteKey() {
        W2L_Settings__c cfg = W2L_Settings__c.getOrgDefaults();
        return cfg != null ? cfg.ReCaptcha_Site_Key__c : null;
    }

    // ─── Core logic (shared) ─────────────────────────────────────────────────

    private static SubmitResult process(Map<String, Object> body) {
        // 1. reCAPTCHA
        String token = (String) body.get('captchaToken');
        if (String.isBlank(token) || !verifyCaptcha(token)) {
            return new SubmitResult(403, false,
                'reCAPTCHA verification failed. Please try again.');
        }

        // 2. Rate limit
        if (currentMonthCount() >= getMonthlyLimit()) {
            return new SubmitResult(429, false,
                'Monthly submission limit reached. Please try again next month.');
        }

        // 3. Required field validation
        String lastName = sanitize((String) body.get('lastName'));
        String company  = sanitize((String) body.get('company'));
        String email    = sanitize((String) body.get('email'));

        if (String.isBlank(lastName) || String.isBlank(company) || String.isBlank(email)) {
            return new SubmitResult(400, false,
                'Last Name, Company, and Email are required.');
        }
        if (!isValidEmail(email)) {
            return new SubmitResult(400, false, 'Please enter a valid email address.');
        }

        // 4. Insert Lead + submission record
        Lead lead = new Lead(
            FirstName  = sanitize((String) body.get('firstName')),
            LastName   = lastName,
            Company    = company,
            Email      = email,
            Phone      = sanitize((String) body.get('phone')),
            Website    = sanitize((String) body.get('website')),
            Street     = sanitize((String) body.get('street')),
            City       = sanitize((String) body.get('city')),
            State      = sanitize((String) body.get('state')),
            PostalCode = sanitize((String) body.get('postalCode')),
            Country    = sanitize((String) body.get('country')),
            LeadSource = 'Web'
        );
        insert lead;
        insert new W2L_Submission__c(Lead__c = lead.Id);

        return new SubmitResult(200, true, 'Thank you! We will be in touch soon.');
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static Boolean verifyCaptcha(String token) {
        W2L_Settings__c cfg = W2L_Settings__c.getOrgDefaults();
        String secret = cfg != null ? cfg.ReCaptcha_Secret_Key__c : null;
        if (String.isBlank(secret)) return false;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(RECAPTCHA_VERIFY_URL);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(
            'secret='    + EncodingUtil.urlEncode(secret, 'UTF-8') +
            '&response=' + EncodingUtil.urlEncode(token,  'UTF-8'));
        req.setTimeout(10000);

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) return false;
            Map<String, Object> parsed =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return parsed.get('success') == true;
        } catch (Exception e) {
            return false;
        }
    }

    private static Integer getMonthlyLimit() {
        W2L_Settings__c cfg = W2L_Settings__c.getOrgDefaults();
        return (cfg != null && cfg.Monthly_Submission_Limit__c != null)
            ? Integer.valueOf(cfg.Monthly_Submission_Limit__c)
            : DEFAULT_MONTHLY_LIMIT;
    }

    private static Integer currentMonthCount() {
        Date firstOfMonth = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        return [SELECT COUNT() FROM W2L_Submission__c WHERE CreatedDate >= :firstOfMonth];
    }

    private static Boolean isValidEmail(String addr) {
        return String.isNotBlank(addr) &&
               Pattern.matches(
                   '^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$',
                   addr.trim());
    }

    private static String sanitize(String val) {
        return String.isBlank(val) ? null : val.trim().stripHtmlTags();
    }
}
