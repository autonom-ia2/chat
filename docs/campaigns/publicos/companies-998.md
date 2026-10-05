# Companies from spreadsheet imports (#998)

Rules: PRD of the audiences epic (#990), §8.2 "Empresa" and acceptance group C1–C7.
This branch ships only the service and its spec. Wiring into `CampaignImports::Importer`
happens on top of #992 (SchemaResolver/Validator/Importer changes), so this document is
the contract for that step.

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

## How the importer should call it (on top of #992)

Rows produced by the SchemaResolver/Validator need `company_name` and `email` (both
optional). Inside the importer:

```ruby
def company_linker
  @company_linker ||= CampaignImports::CompanyLinker.new(account, enabled: campaign_import.<create_companies switch>)
end

def import_block(block, label_records)
  company_linker.prepare(block)  # before or inside the block transaction
  ActiveRecord::Base.transaction do
    # ... per row, inside the row savepoint, after the contact exists:
    result = company_linker.link(contact, company_name: row[:company_name], email: row[:email])
    # persist result.status on the campaign_import_row (e.g. company_result) and result.company&.id
  end
end
```

- Call `link` inside the row savepoint, after the contact is created/found, so a failed row
  rolls back its company together with the contact.
- Use a single linker instance for the whole import (the dedupe and the indexes live in it).
- Persist the per-row `status` on the import row. On a retried import the linker is new, so
  `summary` only covers the current run; final numbers for the screen should be aggregated
  from the persisted row statuses (`created` rows = companies created, `kept_other` rows =
  "mantidas", etc.), the same way `finish_import!` aggregates contacts today. Rows already
  imported are skipped by the importer, so they are not linked twice.
- C7 ("Remover do público" does not undo companies) holds by construction: the linker has no
  unlink path, and the undo/removal flows must not call `ContactMembershipService#remove`.

## Open points

- Created companies get no `domain`, even when the row has a business e-mail. Setting it would
  make the next rows with that e-mail match by domain, but it also triggers the favicon job
  and can collide with the per-account unique domain. PRD says "cria com o nome"; kept as is.
- A contact that keeps another company does not create the spreadsheet company (avoids empty
  companies). If the preview should count it as "nova", the preview must use the same rule.
- No unique index on company name: two imports running at the same time on the same account
  can each create the same name once. Within one import there is never a duplicate.
