module Crm
  module Calendar
    # Orchestrates a PUBLIC (unauthenticated) booking against an enabled booking
    # profile. There is NO User in this flow, so it never touches Pundit. Security:
    # all input is sanitized/validated, the chosen slot is re-checked against live
    # free/busy + the profile rules to prevent double-booking, and the booker email
    # becomes the card's contact email so Crm::Meetings::Creator has a reachable
    # guest (and the booker receives the real .ics invite + Meet/Teams link).
    #
    # Raises ArgumentError(<code>) for any rejectable condition; the controller maps
    # every failure to a single generic public error (no stack trace, no PII).
    class PublicBookingService
      EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/.freeze
      CONTROL_CHARS = /[\x00-\x1f\x7f]/.freeze
      MAX_NAME_LENGTH = 120
      MAX_EMAIL_LENGTH = 254
      DEFAULT_REMINDER_MINUTES = 15

      # Signed (HMAC) verifier used for the email-verification token. No DB table:
      # the booker's intent is carried in a tamper-proof, expiring payload, and the
      # meeting is only created once they prove control of the email by opening the
      # link (which echoes the token back).
      MESSAGE_VERIFIER_PURPOSE = 'crm_public_booking'.freeze
      TOKEN_TTL = 30.minutes
      # Advisory-lock namespaces (first key of pg_advisory_xact_lock(int,int)) so an
      # inbox-id lock and an agent-id lock with the same numeric id never collide.
      LOCK_NS_INBOX = 1
      LOCK_NS_AGENT = 2

      Result = Struct.new(:confirmed, :join_url, :starts_at, keyword_init: true)
      InitiateResult = Struct.new(:token, :name, :email, :starts_at, keyword_init: true)

      def self.message_verifier
        Rails.application.message_verifier(MESSAGE_VERIFIER_PURPOSE)
      end

      # STEP 2 (called from the email link). Verifies the signed token, re-resolves
      # the still-enabled profile, then — under an advisory lock + transaction —
      # re-checks the slot fail-closed and creates the contact/card/meeting. Any
      # tamper/expiry/disabled-profile condition collapses to ArgumentError
      # 'invalid_token'; the controller maps every failure to one generic error.
      def self.confirm(token:)
        payload = verify_token!(token)
        profile = Crm::AgentBookingProfile.enabled.find_by(id: payload['p'])
        raise ArgumentError, 'invalid_token' if profile.blank?

        # per_agent: the token carries the link id ('l'). Re-resolve it (still enabled
        # AND belonging to THIS profile) so the host/owner/mailbox can't be swapped.
        link = nil
        if payload['l'].present?
          link = profile.agent_booking_links.enabled.find_by(id: payload['l'])
          raise ArgumentError, 'invalid_token' if link.blank?
        end

        new(
          profile: profile,
          name: payload['n'],
          email: payload['e'],
          starts_at: payload['s'],
          link: link
        ).confirm_booking!
      end

      def self.verify_token!(token)
        message_verifier.verify(token.to_s)
      rescue ActiveSupport::MessageVerifier::InvalidSignature,
             ActiveSupport::MessageEncryptor::InvalidMessage
        raise ArgumentError, 'invalid_token'
      end

      # link (optional) — a per-agent booking link. When present the booking is
      # attributed to link.agent and lands on link.inbox; otherwise it falls back to
      # the profile's default_assignee + inbox (fixed mode).
      def initialize(profile:, name:, email:, starts_at:, link: nil)
        @profile = profile
        @raw_name = name
        @raw_email = email
        @raw_starts_at = starts_at
        @link = link
      end

      # STEP 1 (called from the public form). Validates + sanitizes input and
      # re-checks the slot FAIL-CLOSED, but creates NOTHING. Returns a signed token
      # the controller emails to the booker. No meeting exists until #confirm.
      def initiate
        validate_inputs!
        validate_slot_available!

        InitiateResult.new(token: build_token, name: name, email: email, starts_at: starts_at.iso8601)
      end

      # STEP 2 body. Serializes confirmations for the SAME inbox via a Postgres
      # transaction-level advisory lock so two concurrent confirms cannot both
      # create overlapping meetings — the second one re-checks the slot inside the
      # lock, sees the first's meeting as busy, and is rejected ('slot_unavailable').
      def confirm_booking!
        created_card = nil
        result =
          ActiveRecord::Base.transaction do
            acquire_booking_lock!

            validate_slot_available!

            contact = find_or_create_contact!
            created_card = create_lead_card!(contact)
            meeting = schedule_meeting!(created_card)

            Result.new(confirmed: true, join_url: meeting.online_meeting_url, starts_at: meeting.starts_at&.iso8601)
          end

        # AFTER commit: push the new lead card to subscribed agents so their Kanban
        # board AND calendar refetch in realtime (the public booking happens with no
        # agent client driving the refresh, so without this the calendar only updates
        # on a manual reload). Fail-safe — the booking already succeeded.
        broadcast_card_created(created_card)
        result
      end

      private

      attr_reader :profile, :link

      def account
        @account ||= profile.account
      end

      # The booking host/owner: the link's agent (per_agent) or the profile's default
      # assignee (fixed). Crm::Meeting REQUIRES a User as created_by.
      def host_agent
        @host_agent ||= link&.agent || profile.default_assignee
      end

      # The calendar mailbox the event lands on: the link's inbox (the agent's chosen
      # mailbox) or the profile's inbox (fixed).
      def effective_inbox
        @effective_inbox ||= link&.inbox || profile.inbox
      end

      def shared_calendar?
        channel = effective_inbox&.channel
        channel.is_a?(Channel::Email) && channel.calendar_shared?
      end

      # Serialize concurrent confirms. SHARED mailbox: lock on the HOST AGENT, because
      # the conflict check is per-agent (created_by) — locking the inbox would let the
      # SAME agent double-book across two different shared mailboxes. Dedicated mailbox:
      # lock on the inbox (the conflict check is inbox-scoped).
      def acquire_booking_lock!
        namespace, key = if shared_calendar? && host_agent
                           [LOCK_NS_AGENT, host_agent.id]
                         else
                           [LOCK_NS_INBOX, effective_inbox.id]
                         end
        ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{namespace.to_i}, #{key.to_i})")
        # Agendamento v2 (#1188) reserva o mesmo responsável sob o lock de agente: tomado DEPOIS do da caixa (mesma
        # ordem do Crm::BookingV2::Booker), para v1 e v2 não marcarem o mesmo horário nem travarem em ciclo.
        return if host_agent.blank? || namespace == LOCK_NS_AGENT

        ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NS_AGENT}, #{host_agent.id.to_i})")
      end

      def name
        @name ||= sanitize_text(@raw_name).to_s.first(MAX_NAME_LENGTH).strip
      end

      def email
        @email ||= sanitize_text(@raw_email).to_s.downcase.strip.first(MAX_EMAIL_LENGTH)
      end

      def starts_at
        @starts_at ||= parse_starts_at!
      end

      def ends_at
        starts_at + profile.duration_minutes.minutes
      end

      def timezone
        profile.resolved_timezone
      end

      def validate_inputs!
        raise ArgumentError, 'invalid_email' unless email.match?(EMAIL_REGEX)
        raise ArgumentError, 'invalid_name' if name.blank?
      end

      def parse_starts_at!
        raise ArgumentError, 'invalid_starts_at' if @raw_starts_at.blank?

        Time.iso8601(@raw_starts_at.to_s)
      rescue ArgumentError
        raise ArgumentError, 'invalid_starts_at'
      end

      def build_token
        payload = { 'p' => profile.id, 'n' => name, 'e' => email, 's' => starts_at.iso8601 }
        payload['l'] = @link.id if @link.present?
        self.class.message_verifier.generate(payload, expires_in: TOKEN_TTL)
      end

      # Re-check the chosen slot against the SAME computation the slots endpoint
      # uses (live free/busy + working hours + buffer + window). Prevents a stale
      # client from double-booking or booking outside the rules.
      #
      # strict:true — fail CLOSED: a provider free/busy error now PROPAGATES out of
      # PublicAvailableSlots (instead of degrading to "no busy intervals") and is
      # re-raised here as ArgumentError 'availability_unavailable', so a booking is
      # never confirmed against an availability state we could not actually verify.
      def validate_slot_available!
        # Local guard FIRST: a meeting just created (e.g. by a concurrent confirm
        # holding then releasing the advisory lock, or a replay of the same token)
        # is the authoritative busy signal. Provider free/busy can lag — and in
        # simulation never reflects a locally-created meeting — so we must not rely
        # on it alone to prevent a double-book.
        raise ArgumentError, 'slot_unavailable' if local_slot_taken?

        local_date = starts_at.in_time_zone(timezone).to_date.to_s
        available = Crm::Calendar::PublicAvailableSlots.new(
          profile: profile, date: local_date, strict: true, inbox: effective_inbox, agent: host_agent
        ).perform
        return if available.any? { |iso| Time.iso8601(iso) == starts_at }

        raise ArgumentError, 'slot_unavailable'
      rescue ArgumentError
        raise
      rescue StandardError
        raise ArgumentError, 'availability_unavailable'
      end

      # True when a still-scheduled meeting overlaps the requested window (buffer on
      # both sides). SHARED mailbox -> scope by the HOST AGENT (so seller A's 14:00
      # never blocks seller B); dedicated mailbox -> scope by the mailbox.
      def local_slot_taken?
        buffer = profile.buffer_minutes.minutes
        scope = Crm::Meeting.where(account_id: account.id, status: :scheduled)
        scope = shared_calendar? ? scope.where(created_by_id: host_agent&.id) : scope.where(inbox_id: effective_inbox.id)
        scope.where('starts_at < ? AND ends_at > ?', ends_at + buffer, starts_at - buffer).exists? || internal_slot_taken?(buffer)
      end

      # Reunião interna (#1188, sem provedor) do mesmo responsável também ocupa o horário.
      def internal_slot_taken?(buffer)
        return false if host_agent.blank?

        Crm::Meeting.where(account_id: account.id, status: :scheduled, provider: :internal, created_by_id: host_agent.id)
                    .where('starts_at < ? AND ends_at > ?', ends_at + buffer, starts_at - buffer).exists?
      end

      def broadcast_card_created(card)
        return if card.blank?

        Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_CREATED)
      rescue StandardError => e
        Rails.logger.error("CRM public booking realtime broadcast failed: #{e.class.name}")
      end

      def find_or_create_contact!
        account.contacts.from_email(email) ||
          account.contacts.create!(name: name.presence || email, email: email)
      end

      def create_lead_card!(contact)
        Crm::Cards::Creator.new(
          account: account,
          user: nil,
          params: {
            pipeline_id: pipeline_id,
            stage_id: stage_id,
            contact_id: contact.id,
            owner_id: host_agent&.id,
            title: card_title(contact),
            currency: 'BRL',
            source: 'public_booking'
          }
        ).perform
      end

      def card_title(contact)
        base = contact.name.presence || name.presence || email
        "#{base} - #{profile.title.presence || 'Agendamento'}".first(255)
      end

      def schedule_meeting!(card)
        Crm::Meetings::Creator.new(
          account: account,
          card: card,
          inbox: effective_inbox,
          scheduled_by: scheduled_by(card),
          params: {
            title: profile.title.presence || card.title,
            description: profile.description,
            starts_at: starts_at,
            ends_at: ends_at,
            timezone: timezone,
            reminder_minutes_before: DEFAULT_REMINDER_MINUTES,
            extra_guests: []
          }
        ).perform
      end

      # No User in a public flow. Crm::Meeting REQUIRES created_by, so we must
      # resolve a real User: prefer the configured default assignee, else the card
      # owner (which itself comes from default_assignee_id). If neither exists the
      # profile is misconfigured for public booking — reject cleanly.
      def scheduled_by(card)
        host_agent || card.owner || (raise ArgumentError, 'no_scheduling_user')
      end

      def pipeline_id
        profile.default_pipeline_id || default_pipeline&.id || (raise ArgumentError, 'no_pipeline_configured')
      end

      def stage_id
        return profile.default_stage_id if profile.default_stage_id.present?

        resolved = default_pipeline&.stages&.order(:position)&.first
        resolved&.id || (raise ArgumentError, 'no_stage_configured')
      end

      def default_pipeline
        @default_pipeline ||= if profile.default_pipeline_id.present?
                                account.crm_pipelines.find_by(id: profile.default_pipeline_id)
                              else
                                account.crm_pipelines.active.order(:id).first
                              end
      end

      def sanitize_text(value)
        return if value.nil?

        # Strip HTML tags + control chars (keeps it safe for storage + display).
        stripped = ActionController::Base.helpers.strip_tags(value.to_s)
        stripped.gsub(CONTROL_CHARS, ' ')
      end
    end
  end
end
