# Store AWS and sandbox readiness

## Verified state on 2026-10-14

This is readiness evidence and a runbook, not an applied configuration or a
deployment authorization. AWS reads were limited to STS and the existing SSM
environment parameter; only presence and non-secret URLs were reported.

| Installation | AWS account / region | Existing environment parameter | OAuth client | Store settings |
| --- | --- | --- | --- | --- |
| Autonomia | 140023375763 / us-east-1 | /chatwoot/prod/env | talkai | All five absent |
| Hub2You | 354307071110 / us-east-1 | /chatwoot/prod/env | chat2you | All five absent |

Both currently use `https://financial.api-autonomia.com`. That live origin is
not a sandbox fallback. No SSM value, credential, IAM policy, database row,
worker schedule or running service was changed by this preparation.

## Required configuration

Each installation and environment needs its own registered namespace/caller:

- `FINANCIAL_STORE_API_KEY`: dedicated installation-scoped key, not Financial
  admin credentials. Financial stores its hash, not the plaintext.
- `FINANCIAL_STORE_ACTOR_ASSERTION_SECRET`: independent HS256 signing secret,
  at least 32 bytes; must differ from the API key and webhook secret.
- `FINANCIAL_STORE_WEBHOOK_SECRET`: independent callback HMAC secret, at least
  32 bytes. Do not reuse the actor signing secret.
- `FINANCIAL_STORE_INSTALLATION_ID`: canonical registered installation namespace.
- `FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID`: existing official Financial product
  UUID, not the OAuth client string or a newly duplicated catalog product.

Namespace IDs and official product/operator mappings still need confirmation
with Financial. Never accept namespace, buyer, role or principal authority from
browser input. Existing Auth access-token refresh and canonical Cognito subject
resolution are reused; no Auth change is proposed in these PRs.

The scoped feature registry is `prospecting`, `email_campaigns` and
`whatsapp_api_campaigns`. This pilot implements activation for prospecting and
linked agents; it does not newly gate the existing campaign features.
Service icons and commercial presentation remain managed in Financial by the
SuperAdmin, and the store renders their catalog values.

## Callback routes

The route added by this PR is exactly `POST /api/autonomia/financial/store-events`.
Future live callback URLs, not yet published or validated, are:

- `https://agents.autonomia.site/api/autonomia/financial/store-events`
- `https://chat.hub2you.ai/api/autonomia/financial/store-events`

The handler validates fresh HMAC headers, namespace, schema, payload size and
event digest; persistence precedes enqueue. Payment callbacks do not by
themselves activate features or agents. An explicit beneficiary reservation,
commit and confirmed grant are required.

## Blocked sandbox gate

Financial's scoped AWS inventory contains only production Financial functions,
with no HML/store-worker deployment and no HML Financial SSM parameters. A usable
isolated gateway sandbox was not confirmed. The store currently uses Stripe
card Checkout, not an Asaas/PIX flow.

A full real-sandbox test needs an explicitly approved isolated Financial and
Chatwoot deployment, database/settings, Identity caller and public HTTPS
callback, plus a dedicated test gateway binding. Do not temporarily reroute
the live financial integration or reuse real customer/payment data to make
that test possible. No payment call is authorized with a live key.

## Safe sequence after the separate deployment gate

1. Approve the isolated environment, budget and immutable SHAs; confirm official
   operator/product mappings and dedicated namespaces.
2. Publish Financial migrations and API/worker infrastructure with caller,
   checkout and worker still disabled. Publish the Chatwoot schema/API without
   enabling store purchases. Use approved workflows, never a production runner.
3. Register each scoped inactive caller and independent secret references;
   merge only those fields into that environment's existing SSM configuration,
   preserving unrelated values. Do not replace the whole parameter with a sample.
4. Validate IAM, caller scope, callback routing and TLS. Enable only the agreed
   test caller/offering and manually scoped event delivery; no automatic agenda.
5. Verify sandbox payment -> official invoice/payment/capture -> subscription
   -> signed inbox -> explicit account capacity -> feature or linked instance.
   Verify replay, limit denial, release/reuse, cancel/resume and paid cutoff.
6. Disable the sandbox pilot, preserve evidence and request a separate live
   release approval. Keep the initial store access SuperAdmin-only.

No infrastructure was provisioned and no new cloud execution cost was incurred
by this verification. Future HML compute/database/network costs need approval.
