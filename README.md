# sf-web-to-lead

A **public, unauthenticated Web-to-Lead** solution for Salesforce with **two entry points**, both
backed by the same Apex controller and the same isolated Experience Cloud guest user.

| Entry point | Where it lives | How it reaches Salesforce |
|-------------|----------------|---------------------------|
| **External form** | `index.html` on **GitHub Pages** (`https://dmvictor83.github.io/sf-web-to-lead/`) | POSTs JSON to a guest **Apex REST** endpoint |
| **In-site form** | `w2lLeadForm` LWC on the **W2L Experience Cloud** site (`.../my.site.com/w2l/`) | Calls Apex directly via **`@AuraEnabled`** (same-origin) |

Both: verify **reCAPTCHA v2** server-side → enforce a **1,000/month** limit → validate + sanitize →
insert a `Lead` (`LeadSource = Web`) + a `W2L_Submission__c` record.

```
External:  GitHub Pages form ──POST text/plain JSON──▶ @HttpPost handlePost ─┐
In-site:   Experience Cloud LWC ──@AuraEnabled────────▶ submitLead ──────────┤
                                                                             ▼
                                                    process() → Lead + W2L_Submission__c
```

---

## Repo layout

```
index.html                         External static form (GitHub Pages)
sfdx-project.json                  SFDX project config
force-app/main/default/
  classes/W2LController*            REST + Aura Apex, shared process()
  classes/W2LControllerTest*       Tests (11, full coverage)
  lwc/w2lLeadForm/                 In-site Experience Cloud form
  staticresources/w2lCaptcha*      reCAPTCHA iframe host (bypasses LWS)
  objects/W2L_Submission__c/       Rate-limit tracking object
  objects/W2L_Settings__c/         Custom setting: reCAPTCHA keys + limit
  profiles/W2L Profile*            Experience Cloud guest, scoped to Lead + submission create
  profiles/Payment Portal Profile* W2L access revoked (guest isolation)
  corswhitelistorigins/GitHubPages*
  remoteSiteSettings/GoogleRecaptcha*
  cspTrustedSites/GoogleRecaptcha*, GoogleRecaptchaStatic*
```

---

## Deploy to a new org

Steps marked **🖐 MANUAL** cannot be done via CLI/metadata — they are Setup UI actions.

### 1. Google reCAPTCHA keys (one-time)
1. Go to [reCAPTCHA admin](https://www.google.com/recaptcha/admin) → register a site.
2. Type: **reCAPTCHA v2 → "I'm not a robot" checkbox**.
3. Copy the **site key** and **secret key**.
4. Under **Domains**, add every host that will show the form (see step 7).

### 2. Authenticate the CLI
```bash
sf org login web --alias devedition
```

### 3. 🖐 MANUAL — Enable Digital Experiences (irreversible)
Required to create the Experience Cloud site that gives W2L its own guest user.
> **Setup → Digital Experiences → Settings → Enable Digital Experiences.**
> Choose your permanent `*.my.site.com` domain and save. **This cannot be undone.**

### 4. Create the W2L Experience Cloud site
```bash
sf community create --name "W2L" \
  --template-name "Build Your Own (LWR)" \
  --url-path-prefix "w2lvforcesite" \
  --target-org devedition
```
> This auto-creates the guest user + **`W2L Profile`** guest profile. The site is served at
> `https://<your-domain>.my.site.com/w2l/`.

### 5. Deploy the metadata
```bash
sf project deploy start --target-org devedition --source-dir force-app
```
> Deploys the Apex, LWC, static resource, objects, profiles, CORS, remote site, and CSP.

### 6. 🖐 MANUAL — Store the reCAPTCHA keys
Create the `W2L_Settings__c` org-default record with your keys and limit:
```bash
sf data create record --target-org devedition --sobject W2L_Settings__c \
  --values "SetupOwnerId=<YourOrgId> ReCaptcha_Site_Key__c=<SITE_KEY> ReCaptcha_Secret_Key__c=<SECRET_KEY> Monthly_Submission_Limit__c=1000"
```
> Or via **Setup → Custom Settings → W2L Settings → Manage → New** (org default).
> The **secret** key stays server-side only — never put it in HTML.

### 7. 🖐 MANUAL — Add hosts to reCAPTCHA allowed domains
In the [reCAPTCHA admin](https://www.google.com/recaptcha/admin) → your site key → **Domains**, add
(hostname only, no `https://`, no path):
- `dmvictor83.github.io` (or your GitHub Pages host) — for the external form
- `<your-domain>.my.site.com` — for the in-site form

### 8. 🖐 MANUAL — Configure the Experience site (Experience Builder)
Open **Setup → Digital Experiences → All Sites → W2L → Builder**, then:
1. Drag the **W2L Lead Form** component onto the **Home** page.
2. **Settings ⚙ → Security & Privacy** → set **Relaxed CSP** (or add `https://www.google.com` and
   `https://www.gstatic.com` as trusted script sources) so the reCAPTCHA iframe loads.
3. **Settings → General** → confirm **Public access** (guest) is enabled.
4. Click **Publish**.
> **Re-publish whenever you change the LWC.** Apex-only changes don't need a republish.

### 9. Update the external form's endpoint
Edit `index.html` → `SF_ENDPOINT` to your org's site host, then push to GitHub Pages:
```js
var SF_ENDPOINT = 'https://<your-domain>.my.site.com/w2l/services/apexrest/w2l/';
```
> Enable GitHub Pages: repo **Settings → Pages → Deploy from branch → main**.

### 10. Verify
```bash
# Should return HTTP 403 (reCAPTCHA rejects the fake token) — proves the endpoint + guest work
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "https://<your-domain>.my.site.com/w2l/services/apexrest/w2l/" \
  -H "Content-Type: text/plain" \
  --data '{"lastName":"T","company":"C","email":"c@e.com","captchaToken":"x"}'
```
Then open each form, complete the reCAPTCHA, and submit → a `Lead` appears in Salesforce.

---

## Gotchas (why the code is the way it is)

- **`text/plain` POST** on the external form avoids the CORS preflight that guest sites don't answer.
- **State & Country picklists** are enabled → the forms submit **full names** ("Texas"), not codes.
- **Lightning Web Security** blocks reCAPTCHA in an LWC → it's sandboxed in an **iframe** static
  resource, with the token returned via `postMessage`.
- LWS also blocks the iframe resize handshake → the reCAPTCHA iframe uses a **fixed height** (610px).
- **`@AuraEnabled` result fields** must each be annotated, or the LWC receives `undefined`.
- reCAPTCHA is **domain-locked** — add every host in the admin console.

See `CLAUDE.md` for the working-in-this-repo notes.
