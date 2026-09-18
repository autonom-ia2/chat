class EmailCampaigns::PreflightLease
  DURATION = 5.minutes

  def initialize(campaign)
    @campaign = campaign
  end

  def acquire(recheck: false)
    @campaign.with_delivery_lock do
      next if unavailable? || live?

      due = EmailCampaigns::RecipientPreflightJob.due(@campaign.email_campaign_recipients.pending)
      next unless recheck || @campaign.preflight_lease_token || due.exists?

      start_pass(recheck)
      # Fence old evidence atomically without updating the whole recipient list.
      # The marker survives expiry; recovery continues the same bounded pass.
      @campaign.preflight_summary = @campaign.preflight_summary.merge('rechecking' => true) if recheck
      rotate
    end
  end

  # Each queued token is consumed once before DNS. Duplicate deliveries cannot join
  # the running chain. A lost enqueue/crashed worker is recoverable after expiry.
  def claim(token, cursor)
    @campaign.with_delivery_lock do
      next unless owns?(token) && @campaign.preflight_cursor == cursor && !unavailable?

      rotate
    end
  end

  def advance(token, cursor)
    # Aggregation is a snapshot, not an admission gate. Never collect under parent
    # locks; publication rechecks ownership after collection (including expiry).
    summary = @campaign.email_campaign_recipients.group(:preflight_status).count unless remaining(cursor).exists?
    @campaign.with_delivery_lock do
      next unless owns?(token) && !unavailable?

      @campaign.preflight_cursor = cursor
      if summary.nil? || remaining(cursor).exists?
        rotate
      else
        persist(preflight_summary: summary, preflight_lease_token: nil, preflight_lease_expires_at: nil)
        nil
      end
    end
  end

  def remaining(cursor)
    scope = @campaign.email_campaign_recipients.pending
    scope = EmailCampaigns::RecipientPreflightJob.due(scope) unless @campaign.preflight_summary['rechecking']
    scope.where('id > ? AND id <= ?', cursor, @campaign.preflight_ceiling)
  end

  def with_holder(token)
    @campaign.with_delivery_lock do
      yield if owns?(token) && !unavailable?
    end
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
    persist(preflight_lease_token: token, preflight_lease_expires_at: DURATION.from_now)
    [token, @campaign.preflight_cursor]
  end

  def persist(attributes)
    # Lease/progress must remain recoverable even on a legacy-invalid campaign.
    # Only lease-owned columns bypass content validation; delivery gates are unchanged.
    @campaign.update_columns( # rubocop:disable Rails/SkipsModelValidations
      **attributes, preflight_cursor: @campaign.preflight_cursor, preflight_ceiling: @campaign.preflight_ceiling,
                    preflight_summary: attributes.fetch(:preflight_summary, @campaign.preflight_summary), updated_at: Time.current
    )
  end
end
