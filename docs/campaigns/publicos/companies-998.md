# Companies from spreadsheet imports (#998)

Rules: PRD of the audiences epic (#990), §6.6 item 4, §8.1, §8.2 "Empresa" and acceptance
group C1–C7. Built on top of #992 (audience flow: SpreadsheetReader, AudienceValidator,
Importer). Only Públicos (`options.flow = "audience"`) touch companies; the old campaign base
flow is unchanged.

## Service

`app/services/campaign_imports/company_linker.rb` — `CampaignImports::CompanyLinker`.

It lives in OSS `app/` because the importer does; it touches `Company`,
`Companies::ContactMembershipService` and `Companies::BusinessEmailDetectorService`
(Enterprise) only after `CompanyLinker.available?(account)` says the Enterprise overlay is
loaded and the account has the `companies` feature.

```ruby
linker = CampaignImports::CompanyLinker.new(account, enabled: create_and_link_switch)
linker.active?                      # false when the switch is off, Company is undefined or the flag is off

linker.prepare(block_rows)          # block_rows: [{ company_name:, email: }, ...]
result = linker.link(contact, company_name: row[:company_name], email: row[:email])
result.status                       # :created | :reused | :kept_other | :none
result.company                      # Company resolved from the spreadsheet (nil for :none,
                                    #   and for :kept_other when that company does not exist)
result.linked?                      # true when this call set contact.company

linker.summary
# => { companies_created:, companies_reused:, contacts_linked:, contacts_kept: }

CampaignImports::CompanyLinker.normalize_name('Corretora  São Paulo') # => "corretora sao paulo"
```

### Rules

| Step | Behaviour |
|---|---|
| Blank company value, switch off, feature off, no Enterprise | `:none`, nothing written |
| Lookup 1 | domain of the row e-mail, only if a company of the account has that `domain` **and** the e-mail is a business e-mail (`Companies::BusinessEmailDetectorService`) |
| Lookup 2 | normalized name: NFKD, accents removed, downcase, whitespace collapsed; exact comparison, punctuation kept. Oldest company wins if the account already has duplicates |
| Contact has another company | `:kept_other`, contact untouched, **no company created** |
| Contact has the same company | `:reused`, `linked? == false` |
| Company found, contact without company | `:reused`, linked |
| Not found, contact without company | `:created` with the name as written (trimmed, cut to `Limits::COMPANY_NAME_LENGTH_LIMIT`), no domain, linked |
| Same normalized name later in the same import | `:reused` (in-memory index) — one company per name per import |

Linking goes through `Companies::ContactMembershipService#assign` (keeps
`companies.contacts_count` and `additional_attributes['company_name']` in step) with
`contact.skip_company_auto_association = true`, so Enterprise's e-mail after_commit does not
create a second company from the e-mail domain.

### Counters

- `companies_created`: companies created by this import.
- `companies_reused`: distinct companies that existed **before** the import and were used
  (linked or already the contact's). Companies created earlier in the same import do not count.
- `contacts_linked`: rows where `contact.company` was set.
- `contacts_kept`: rows counted as "mantida" (`:kept_other`).

Every increment, and every company added to the in-memory index, is undone through
`ActiveRecord::Base.current_transaction.after_rollback` when the row savepoint (or the block
transaction) rolls back. A rolled-back row therefore never leaves a cached company id that
no longer exists, nor a counter that is too high.

### Performance

- First use per import: one `pluck(:id, :name, :domain)` over the account's companies to
  build the name and domain indexes (memoized for the whole import).
- `prepare(block)`: one query that loads the `Company` records the block resolves to.
- `link`: no read queries for prepared rows; writes are the company insert (only on
  `:created`) and the contact update with its counter cache.

Company lookup (domain, then normalized name) lives in `CampaignImports::CompanyResolver`
(read-only), shared by the linker and by the preview, so both apply the same rules.

## Data (migration `20261005110000_add_company_columns_to_campaign_imports`)

| Table | Column | |
|---|---|---|
| `campaign_import_rows` | `company_id` (bigint, index) | company the spreadsheet named: the one linked, or the one kept out for `kept_other` (nil when it did not exist) |
| `campaign_import_rows` | `company_result` | `created` \| `reused` \| `kept_other` \| `none` (audience rows); nil on old imports and on failed rows |
| `campaign_imports` | `companies_created_count` | rows `created` (one per company) |
| `campaign_imports` | `companies_reused_count` | distinct `company_id` of `reused` rows that no row of the import created |
| `campaign_imports` | `companies_kept_count` | rows `kept_other` ("mantidas") |
| `campaign_imports` | `company_contacts_linked_count` | rows `created` + `reused` (contact ends linked to the spreadsheet company, including a contact that already had it) |
| `campaign_imports` | `options.create_companies` | "Criar e ligar" switch; absent = on |

The counters are computed in `Importer#finish_import!` (and on an aborted import) **from the
persisted rows** (`CampaignImports::ImportCompanies#counters`), not from `linker.summary`: a
retried job starts a new linker and skips rows already imported, and the numbers still cover
the whole import.

## Importer

`CampaignImports::ImportCompanies` (one per run, audience only):

- `prepare(block)` before each block transaction: one query for the companies of the block.
- `link(contact, row)` inside the row savepoint, after the contact is found/created and its
  blank fields filled; the result goes to `company_id`/`company_result` of the row. A row that
  fails rolls back its company with it and keeps both columns nil.
- Every audience contact gets `skip_company_auto_association = true`: companies come only
  from the company column. Without it, Enterprise's after_commit would create a company from a
  business e-mail domain even with the switch off (C5) and the preview would be wrong.

## Preview before saving

`CampaignImports::CompanyPreview`, called by `AudienceValidator` when the audience becomes
`ready_to_confirm`, read-only. Stored in `validation_summary.companies`:

```json
{ "available": true, "rows_with_company": 20000, "companies_created": 199,
  "companies_reused": 1, "contacts_linked": 20000, "contacts_kept": 0 }
```

- `available: false` (and nothing else) when the account has no `companies` feature or the
  Enterprise overlay is absent: the screen hides the block (C6).
- Computed regardless of the switch, so turning "Criar e ligar" on/off needs no revalidation.
- It walks the valid rows in import order: company by `CompanyResolver`; contact by the
  importer's match (phone with or without the 9th digit, then e-mail without case), loaded in
  batches of 1.000 keys; a contact with another company is `contacts_kept`; a would-be-new
  company is counted once per normalized name. Equal to the final counters when companies and
  contacts do not change between validation and saving (spec checks it in C1–C4 and a mixed
  file).

## API

- `POST /campaign_imports` with `name` accepts `create_companies` (`"false"` turns it off;
  default on).
- `PATCH /campaign_imports/:id/companies` `{ "create_companies": true|false }` —
  `campaign_manage`; allowed while `uploaded`, `validating`, `needs_column_choice`,
  `ready_to_confirm` or `validation_failed`. Errors `422`:
  `campaign_import.invalid_companies_choice`, `campaign_import.companies_choice_not_available`,
  `campaign_import.not_an_audience`.
- Object: `create_companies` (boolean) and
  `companies: { created, reused, contacts_linked, kept }` (final numbers; zero before saving).
  Preview in `validation_summary.companies`. Details in `api-992.md` §4 and §9.

## C7

"Remover do público" / undo labels does not undo companies: neither `UndoLabels` nor the
linker has an unlink path, and neither calls `ContactMembershipService#remove` (spec C7).

## Open points

- With the switch on and a blank company cell, the e-mail domain auto-association is also
  skipped (companies only from the column). Chatwoot's default would create one from a
  business e-mail. Decision for the product owner.
- Created companies get no `domain`, even when the row has a business e-mail. Setting it would
  make the next rows with that e-mail match by domain, but it also triggers the favicon job
  and can collide with the per-account unique domain. PRD says "cria com o nome"; kept as is.
- A contact that keeps another company does not create the spreadsheet company (avoids empty
  companies); the preview follows the same rule.
- No unique index on company name: two imports running at the same time on the same account
  can each create the same name once. Within one import there is never a duplicate.
