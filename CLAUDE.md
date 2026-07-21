# CLAUDE.md — sf-web-to-lead

Guidance for Claude Code (and humans) working in this repo.

## What this project is

A **public, unauthenticated Web-to-Lead** solution for Salesforce with **two entry points**, both
backed by the same Apex controller and the same isolated Experience Cloud guest user:

1. **External page** — a static HTML form (`index.html`) hosted on **GitHub Pages**. It POSTs JSON
   to a Salesforce guest **Apex REST** endpoint.
2. **In-site page** — an **LWC** (`w2lLeadForm`) placed on a public **Experience Cloud** site page.
   It calls the same Apex directly via `@AuraEnabled` (same-origin, no CORS).

Both flows: verify Google **reCAPTCHA v2** server-side, enforce a **1,000/month** rate limit,
validate + sanitize input, then insert a `Lead` + a `W2L_Submission__c` tracking record.

## Architecture

```
External:  GitHub Pages form  --POST text/plain JSON-->  @HttpPost handlePost  (REST)
In-site:   Experience Cloud LWC  --@AuraEnabled-->        submitLead            (Apex)
                                                     \
                                                      -> process() [shared] -> Lead + W2L_Submission__c
```

- Org: Developer Edition, CLI alias **`devedition`** (instance `orgfarm-6c5e2e6da2-dev-ed`).
- Guest user: **`W2L Profile`** on the **W2L** Experience Cloud site (URL path `w2lvforcesite`,
  served at `/w2l/`). Scoped to *only* `Lead` + `W2L_Submission__c` create — isolated from the
  payment site's guest.

## Metadata in this repo

| Type | API Name | Purpose |
|------|----------|---------|
| ApexClass | `W2LController` | `@HttpPost` REST + `@AuraEnabled` submitLead + shared `process()` |
| ApexClass | `W2LControllerTest` | Full coverage (captcha, rate limit, validation, both entry points) |
| LWC | `w2lLeadForm` | In-site Experience Cloud form; reCAPTCHA via sandboxed iframe |
| StaticResource | `w2lCaptcha` | HTML page hosting reCAPTCHA in an iframe (bypasses Lightning Web Security) |
| CustomObject | `W2L_Submission__c` | One record per submission; used for monthly rate-limit counting |
| CustomObject | `W2L_Settings__c` | Hierarchy custom setting: reCAPTCHA keys + monthly limit |
| Profile | `W2L Profile` | Experience Cloud guest profile, scoped to Lead + W2L_Submission__c create |
| CorsWhitelistOrigin | `GitHubPages` | Allows `dmvictor83.github.io` |
| RemoteSiteSetting | `GoogleRecaptcha` | Apex callout to `https://www.google.com` (siteverify) |
| CspTrustedSite | `GoogleRecaptcha`, `GoogleRecaptchaStatic` | reCAPTCHA assets |

## Hard-won gotchas (do not regress these)

- **CORS (external page):** send the POST as `Content-Type: text/plain` — this keeps it a CORS
  "simple request" so the browser skips the OPTIONS preflight, which Salesforce guest sites don't
  answer. The Apex reads the raw body and JSON-parses it regardless.
- **State & Country picklists are ON** in this org — `Lead.State`/`Country` need **full names**
  ("Texas", "United States"), not codes. Both forms use dropdowns of full names.
- **Lightning Web Security blocks Google reCAPTCHA** inside an LWC (it injects `<meta>` into
  `<head>`). Fix: host the widget in a static-resource HTML page loaded via `<iframe>`; the token
  comes back via `postMessage`.
- **LWS also blocks the iframe→parent resize handshake** on guest LWR sites → the reCAPTCHA image
  challenge can't auto-resize. Fix: a **fixed-height iframe** (610px) that always fits the challenge.
- **`@AuraEnabled` returning a custom Apex class:** every field must be annotated `@AuraEnabled`
  or it returns `undefined` to the LWC (symptom: Lead created but UI shows a generic error).
- **reCAPTCHA is domain-locked:** every host must be added in the reCAPTCHA admin console
  (`dmvictor83.github.io`, the `my.site.com` host, etc.).
- **LWC changes need the Experience site RE-PUBLISHED** to reach the live site. Apex changes do not.

## Deploy

See `README.md` for the full new-org deploy guide, including the manual Setup steps that can't be
done via CLI (enabling Digital Experiences, storing reCAPTCHA keys, reCAPTCHA domains, publishing).

## Conventions

- Never hardcode the reCAPTCHA **secret** key anywhere client-side — it lives only in
  `W2L_Settings__c` (server-side). The **site** key is public and may appear in HTML/static resource.
- On every push, bump `README.md`/changelog notes and add a timestamped git tag.
