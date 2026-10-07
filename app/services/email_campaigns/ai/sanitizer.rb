# Cleans the MJML of the AI (also the editor's saves, the gallery and adjustments): web-search markdown citations
# become links (CitationLinks), then the markup goes through the allowlist shared with the import (MarkupPolicy) on
# the parsed tree and the parsed HTML of every ending tag (MarkupCleaner, #1104) — script and other active elements,
# event handlers, URL schemes other than http/https/mailto/tel (however encoded) and unsafe CSS never stay. Last,
# exactly one locked footer with the {{ unsubscribe_url }} link (LockedFooter, #1081), stored as canonical MJML —
# explicit close tags, flat mj-attributes (MjmlCanonicalizer, #1074). Idempotent. No regex.
class EmailCampaigns::Ai::Sanitizer
  # Safety-net footer appended when the e-mail has no unsubscribe link: the shared one (lockedFooter.json).
  FALLBACK_FOOTER = EmailCampaigns::LockedFooter::MJML

  def initialize(mjml)
    @mjml = mjml.to_s
  end

  def perform
    cleaned = EmailCampaigns::Ai::MarkupCleaner.call(EmailCampaigns::Ai::CitationLinks.call(@mjml))
    EmailCampaigns::LockedFooter.ensure(cleaned)
  end
end
