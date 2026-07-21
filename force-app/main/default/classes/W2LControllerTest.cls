@IsTest
private class W2LControllerTest {

    @TestSetup
    static void makeData() {
        insert new W2L_Settings__c(
            SetupOwnerId                = UserInfo.getOrganizationId(),
            ReCaptcha_Site_Key__c       = 'site-key-test',
            ReCaptcha_Secret_Key__c     = 'secret-key-test',
            Monthly_Submission_Limit__c = 5
        );
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static RestRequest buildRequest(Map<String, Object> body) {
        RestRequest req     = new RestRequest();
        req.requestURI      = '/services/apexrest/w2l/';
        req.httpMethod      = 'POST';
        req.requestBody     = Blob.valueOf(JSON.serialize(body));
        req.addHeader('Content-Type', 'application/json');
        return req;
    }

    private static Map<String, Object> validBody(String captchaToken) {
        return new Map<String, Object>{
            'firstName'    => 'Jane',
            'lastName'     => 'Smith',
            'company'      => 'ACME Corp',
            'email'        => 'jane@acme.com',
            'phone'        => '555-1234',
            'website'      => 'https://acme.com',
            'street'       => '123 Main St',
            'city'         => 'Austin',
            'state'        => 'Texas',
            'postalCode'   => '78701',
            'country'      => 'United States',
            'captchaToken' => captchaToken
        };
    }

    private static Map<String, Object> parseResponse() {
        String body = RestContext.response.responseBody.toString();
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    // ─── Tests ────────────────────────────────────────────────────────────────

    @IsTest
    static void testSuccess() {
        RestContext.request  = buildRequest(validBody('good-token'));
        RestContext.response = new RestResponse();
        Test.setMock(HttpCalloutMock.class, new CaptchaSuccessMock());

        Test.startTest();
        W2LController.handlePost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, parseResponse().get('success'));
        System.assertEquals(1, [SELECT COUNT() FROM Lead]);
        System.assertEquals(1, [SELECT COUNT() FROM W2L_Submission__c]);
        System.assertEquals('Web', [SELECT LeadSource FROM Lead LIMIT 1].LeadSource);
    }

    @IsTest
    static void testCaptchaFails() {
        RestContext.request  = buildRequest(validBody('bad-token'));
        RestContext.response = new RestResponse();
        Test.setMock(HttpCalloutMock.class, new CaptchaFailMock());

        Test.startTest();
        W2LController.handlePost();
        Test.stopTest();

        System.assertEquals(403, RestContext.response.statusCode);
        System.assertEquals(false, parseResponse().get('success'));
        System.assertEquals(0, [SELECT COUNT() FROM Lead]);
    }

    @IsTest
    static void testMissingCaptchaToken() {
        Map<String, Object> body = validBody(null);
        body.remove('captchaToken');
        RestContext.request  = buildRequest(body);
        RestContext.response = new RestResponse();

        Test.startTest();
        W2LController.handlePost();
        Test.stopTest();

        System.assertEquals(403, RestContext.response.statusCode);
    }

    @IsTest
    static void testMissingRequiredFields() {
        Map<String, Object> body = validBody('good-token');
        body.remove('lastName');
        RestContext.request  = buildRequest(body);
        RestContext.response = new RestResponse();
        Test.setMock(HttpCalloutMock.class, new CaptchaSuccessMock());

        Test.startTest();
        W2LController.handlePost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM Lead]);
    }

    @IsTest
    static void testInvalidEmail() {
        Map<String, Object> body = validBody('good-token');
        body.put('email', 'not-an-email');
        RestContext.request  = buildRequest(body);
        RestContext.response = new RestResponse();
        Test.setMock(HttpCalloutMock.class, new CaptchaSuccessMock());

        Test.startTest();
        W2LController.handlePost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void testRateLimitEnforced() {
        List<W2L_Submission__c> subs = new List<W2L_Submission__c>();
        for (Integer i = 0; i < 5; i++) subs.add(new W2L_Submission__c());
        insert subs;

        RestContext.request  = buildRequest(validBody('good-token'));
        RestContext.response = new RestResponse();
        Test.setMock(HttpCalloutMock.class, new CaptchaSuccessMock());

        Test.startTest();
        W2LController.handlePost();
        Test.stopTest();

        System.assertEquals(429, RestContext.response.statusCode);
        System.assertEquals(0, [SELECT COUNT() FROM Lead]);
    }

    @IsTest
    static void testCorsHeadersPresent() {
        RestContext.request  = buildRequest(validBody('good-token'));
        RestContext.response = new RestResponse();
        Test.setMock(HttpCalloutMock.class, new CaptchaSuccessMock());

        Test.startTest();
        W2LController.handlePost();
        Test.stopTest();

        String origin = RestContext.response.headers.get('Access-Control-Allow-Origin');
        System.assertEquals('https://dmvictor83.github.io', origin);
    }

    // ─── Aura/LWC entry point ──────────────────────────────────────────────────

    @IsTest
    static void testSubmitLeadSuccess() {
        Test.setMock(HttpCalloutMock.class, new CaptchaSuccessMock());
        Test.startTest();
        W2LController.SubmitResult r =
            W2LController.submitLead(JSON.serialize(validBody('good-token')));
        Test.stopTest();

        System.assertEquals(200, r.statusCode);
        System.assertEquals(true, r.success);
        System.assertEquals(1, [SELECT COUNT() FROM Lead]);
        System.assertEquals(1, [SELECT COUNT() FROM W2L_Submission__c]);
    }

    @IsTest
    static void testSubmitLeadCaptchaFail() {
        Test.setMock(HttpCalloutMock.class, new CaptchaFailMock());
        Test.startTest();
        W2LController.SubmitResult r =
            W2LController.submitLead(JSON.serialize(validBody('bad-token')));
        Test.stopTest();

        System.assertEquals(403, r.statusCode);
        System.assertEquals(false, r.success);
        System.assertEquals(0, [SELECT COUNT() FROM Lead]);
    }

    @IsTest
    static void testSubmitLeadRateLimit() {
        List<W2L_Submission__c> subs = new List<W2L_Submission__c>();
        for (Integer i = 0; i < 5; i++) subs.add(new W2L_Submission__c());
        insert subs;

        Test.setMock(HttpCalloutMock.class, new CaptchaSuccessMock());
        Test.startTest();
        W2LController.SubmitResult r =
            W2LController.submitLead(JSON.serialize(validBody('good-token')));
        Test.stopTest();

        System.assertEquals(429, r.statusCode);
    }

    @IsTest
    static void testGetSiteKey() {
        System.assertEquals('site-key-test', W2LController.getSiteKey());
    }

    // ─── Mocks ────────────────────────────────────────────────────────────────

    private class CaptchaSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success":true}');
            return res;
        }
    }

    private class CaptchaFailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success":false,"error-codes":["invalid-input-response"]}');
            return res;
        }
    }
}
