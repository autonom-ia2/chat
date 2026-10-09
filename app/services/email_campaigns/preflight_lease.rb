class EmailCampaigns::PreflightLease
  DURATION = 5.minutes

  def initialize(campaign)
    @campaign = campaign
  end

  def acquire(recheck: false)
    @campaign.with_lock do
      next if unavailable? || live?

      reset_pending if recheck
      next unless @campaign.preflight_lease_token || EmailCampaigns::RecipientPreflightJob.due(@campaign.email_campaign_recipients.pending).exists?

      start_pass(recheck)
      rotate
    end
  end

  # Each queued token is consumed once before DNS. Duplicate deliveries cannot join
  # the running chain. A lost enqueue/crashed worker is recoverable after expiry.
  def claim(token, cursor)
    @campaign.with_lock do
      next unless owns?(token) && @campaign.preflight_cursor == cursor && !unavailable?

      rotate
    end
  end

  def advance(token, cursor)
    @campaign.with_lock do
      next unless owns?(token)

      @campaign.preflight_cursor = cursor
      if remaining(cursor).exists?
        rotate
      else
        summary = @campaign.email_campaign_recipients.group(:preflight_status).count
        @campaign.update!(preflight_summary: summary, preflight_lease_token: nil, preflight_lease_expires_at: nil)
        nil
      end
    end
  end

  def remaining(cursor)
    EmailCampaigns::RecipientPreflightJob.due(@campaign.email_campaign_recipients.pending)
                                         .where('id > ? AND id <= ?', cursor, @campaign.preflight_ceiling)
  end

  def holder_scope(token)
    EmailCampaign.where(id: @campaign.id, preflight_lease_token: token).where('preflight_lease_expires_at > ?', Time.current)
  end

  private

  def unavailable?
    @campaign.terminal? || @campaign.recipient_import_active?
  end

  def live?
    @campaign.preflight_lease_expires_at && @campaign.preflight_lease_expires_at > Time.current
  end

  def owns?(token)
    live? && @campaign.preflight_lease_token == token
  end

  def start_pass(recheck)
    # Expired chains resume their durable cursor/ceiling; only a new pass resets it.
    return if @campaign.preflight_lease_token && !recheck

    @campaign.assign_attributes(preflight_cursor: 0, preflight_ceiling: @campaign.email_campaign_recipients.maximum(:id) || 0)
  end

  def rotate
    token = SecureRandom.uuid
    @campaign.update!(preflight_lease_token: token, preflight_lease_expires_at: DURATION.from_now)
    [token, @campaign.preflight_cursor]
  end

  def reset_pending
    # Explicit operator recheck invalidates pending evidence atomically with lease acquisition.
    @campaign.email_campaign_recipients.pending.update_all( # rubocop:disable Rails/SkipsModelValidations
      preflight_status: 'unchecked', preflight_checked_at: nil, preflight_valid_until: nil,
      preflight_reason_code: nil, preflight_suggestion: nil, updated_at: Time.current
    )
  end
end
