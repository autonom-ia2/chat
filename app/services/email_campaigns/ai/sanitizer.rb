# Cleans the MJML of the AI (also the editor's saves, the gallery and adjustments): web-search markdown citations
# become links (CitationLinks), then the markup goes through the allowlist shared with the import (MarkupPolicy) on
# the parsed tree and the parsed HTML of every ending tag (MarkupCleaner, #1104) — script and other active elements,
# event handlers, URL schemes other than http/https/mailto/tel (however encoded), Liquid that could render one, CDATA
# and comments hiding markup, unsafe CSS never stay. Around it,
# exactly one locked footer with the {{ unsubscribe_url }} link (LockedFooter, #1081), stored as canonical MJML —
# explicit close tags, flat mj-attributes (MjmlCanonicalizer, #1074). Idempotent. No regex.
class EmailCampaigns::Ai::Sanitizer
  # Safety-net footer appended when the e-mail has no unsubscribe link: the shared one (lockedFooter.json).
  FALLBACK_FOOTER = EmailCampaigns::LockedFooter::MJML

  def initialize(mjml)
    @mjml = mjml.to_s
  end

  # The footer runs before the cleaning too: it points other platforms' unsubscribe merge tags ({{unsubscribe_link}},
  # *|UNSUB|*) at ours, which the Liquid rule of the cleaning would otherwise neutralize. It runs again after, so a
  # footer link the cleaning had to drop is still guaranteed.
  def perform
    footed = EmailCampaigns::LockedFooter.ensure(EmailCampaigns::Ai::CitationLinks.call(@mjml))
    EmailCampaigns::LockedFooter.ensure(EmailCampaigns::Ai::MarkupCleaner.call(footed))
  end
end
