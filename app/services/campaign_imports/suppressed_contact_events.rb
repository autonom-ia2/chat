# Bulk import and undo write many contacts at once; contact events (webhooks, automation)
# stay off while they run and are restored afterwards.
module CampaignImports::SuppressedContactEvents
  private

  def with_suppressed_contact_events
    previous = Current.suppress_contact_events
    Current.suppress_contact_events = true
    yield
  ensure
    Current.suppress_contact_events = previous
  end
end
