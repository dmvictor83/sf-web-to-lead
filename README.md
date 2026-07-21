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

Each row is one component and what it does. "Used by" shows which entry point relies on it —
**External** (GitHub Pages form), **In-site** (Experience Cloud LWC), or **Both**.

### Root

| File | What it is |
|------|------------|
| `index.html` | The external static form. Deploy this to GitHub Pages. |
| `sfdx-project.json` | SFDX project config so `sf project deploy start` works. |
| `CLAUDE.md` | Architecture notes + gotchas for anyone (or Claude) editing the repo. |
| `README.md` | This file — deploy guide. |

### Salesforce metadata (`force-app/main/default/`)

| Component | Type | Used by | What it does |
|-----------|------|:-------:|--------------|
| `W2LController` | Apex class | Both | The brain. Verifies reCAPTCHA, enforces the monthly limit, validates, inserts the Lead. Exposes a REST method (`@HttpPost`, for the external form) and an Aura method (`@AuraEnabled submitLead`, for the LWC) that share one `process()` method. |
| `W2LControllerTest` | Apex class | — | 11 unit tests covering captcha, rate limit, validation, and both entry points. |
| `w2lLeadForm` | LWC | In-site | The form component you drag onto the Experience Cloud page. |
| `w2lCaptcha` | Static resource | In-site | A tiny HTML page that hosts the reCAPTCHA widget in an `<iframe>`. Needed because Lightning Web Security won't let reCAPTCHA run directly inside an LWC. |
| `W2L_Submission__c` | Custom object | Both | One record is created per submission. The monthly rate limit counts these. |
| `W2L_Settings__c` | Custom setting | Both | Stores the reCAPTCHA **site key**, **secret key**, and **monthly limit**. Read by the Apex at runtime. |
| `W2L Profile` | Profile | In-site | The Experience Cloud site's **guest user** profile, scoped to *only* create `Lead` + `W2L_Submission__c`. This is the isolated identity the public uses. |
| `GitHubPages` | CORS whitelist | External | Allows the browser on `dmvictor83.github.io` to read the endpoint's response. |
| `GoogleRecaptcha` | Remote site setting | Both | Lets the Apex make its server-side callout to Google to verify the token. |
| `GoogleRecaptcha`, `GoogleRecaptchaStatic` | CSP trusted sites | Both | Allow the reCAPTCHA scripts/assets to load in the browser. |

> Every metadata component is actually two files — the component plus a `*-meta.xml` descriptor.
> They're listed here once for clarity.

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
