# == Schema Information
#
# Table name: email_campaigns
#
#  id                      :bigint           not null, primary key
#  ai_completed_at         :datetime
#  ai_error                :string
#  ai_generation_token     :string
#  ai_requested_at         :datetime
#  ai_status               :integer          default("idle"), not null
#  ai_subject_variants     :jsonb            not null
#  body_html               :text
#  body_mjml               :text
#  bounced_count           :integer          default(0), not null
#  clicked_count           :integer          default(0), not null
#  complained_count        :integer          default(0), not null
#  delivered_count         :integer          default(0), not null
#  delivery_mode           :integer          default("ses"), not null
#  failed_count            :integer          default(0), not null
#  from_email              :string
#  from_name               :string
#  last_error              :text
#  name                    :string           not null
#  opened_count            :integer          default(0), not null
#  preheader               :string
#  recipients_count        :integer          default(0), not null
#  reply_to                :string
#  scheduled_at            :datetime
#  sent_at                 :datetime
#  sent_count              :integer          default(0), not null
#  ses_configuration_set   :string
#  status                  :integer          default("draft"), not null
#  subject                 :string
#  suppressed_count        :integer          default(0), not null
#  unsubscribed_count      :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  ai_provider_response_id :string
#  sender_identity_id      :bigint
#  sender_inbox_id         :bigint
#
# Indexes
#
#  idx_email_campaigns_account_status_scheduled  (account_id,status,scheduled_at)
#  index_email_campaigns_on_account_id           (account_id)
#  index_email_campaigns_on_sender_identity_id   (sender_identity_id)
#  index_email_campaigns_on_sender_inbox_id      (sender_inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (sender_identity_id => email_sender_identities.id)
#  fk_rails_...  (sender_inbox_id => inboxes.id) ON DELETE => nullify
#
class EmailCampaign < ApplicationRecord
  belongs_to :account
  # Modo SES: domínio verificado. Modo direct_inbox: envio direto pela caixa webmail conectada.
  belongs_to :sender_identity, class_name: 'EmailSenderIdentity', optional: true
  belongs_to :sender_inbox, class_name: 'Inbox', optional: true

  has_many :email_campaign_import_issues, dependent: :destroy
  has_many :email_campaign_imports, dependent: :destroy
  has_one :latest_recipient_import, -> { order(id: :desc) }, class_name: 'EmailCampaignImport',
                                                             inverse_of: :email_campaign, dependent: nil
  has_many :email_campaign_recipients, dependent: :destroy
  has_many :email_events, through: :email_campaign_recipients, source: :email_events

  has_many_attached :builder_assets

  enum status: {
    draft: 0, scheduled: 1, sending: 2, sent: 3, paused: 4, canceled: 5, failed: 6
  }

  # ses = domínio verificado no SES (massa, padrão). direct_inbox = pela própria caixa
  # (webmail conectado), baixo volume + throttle, para o pequeno negócio.
  enum delivery_mode: { ses: 0, direct_inbox: 1 }

  # Estado da geração de e-mail por IA (assíncrona/durável — modo background da OpenAI).
  # Prefixo `ai_` p/ não colidir com o enum status (que também tem `failed`).
  enum ai_status: { idle: 0, processing: 1, ready: 2, failed: 3 }, _prefix: :ai

  BODY_HTML_MAX = 500_000
  CANCELLATION_BATCH_SIZE = 100

  before_validation { self.from_email = from_email.to_s.strip.downcase.presence }
  # No modo direto, o "De:" é SEMPRE o e-mail da caixa (você envia como a própria conta).
  before_validation :set_direct_from_email, if: -> { direct_inbox? }
  before_validation :sanitize_body_mjml, if: -> { body_mjml_changed? && body_mjml.present? }

  validates :name, presence: true, length: { maximum: 120 }
  # subject is optional for drafts (the AI fills it in the builder); required once the
  # campaign leaves draft. Length cap always applies.
  validates :subject, presence: true, length: { maximum: 250 }, unless: -> { draft? }
  validates :subject, length: { maximum: 250 }
  # body_html is optional for drafts (the dialog creates a draft with name/subject/sender only and
  # fills the body later in the builder); required once the campaign leaves draft.
  validates :body_html, presence: true, unless: -> { draft? }
  validates :body_html, length: { maximum: BODY_HTML_MAX }
  validates :body_mjml, length: { maximum: BODY_HTML_MAX }
  validate  :sender_identity_must_belong_to_account
  validate  :sender_inbox_must_belong_to_account
  validate  :sender_present_for_mode
  validate  :reply_to_format, if: -> { reply_to.present? }
  # A checagem de domínio só vale no modo SES; no modo direto o "De:" é a própria caixa.
  validate  :from_email_matches_sender_domain, if: -> { from_email.present? && ses? }

  scope :due, -> { scheduled.where('scheduled_at <= ?', Time.current) }

  EMAIL_REGEX = URI::MailTo::EMAIL_REGEXP

  def sendable?
    return false unless draft? || scheduled?
    return false if recipient_import_active?

    subject.present? && body_html.present? && sender_ready? && sendable_recipients?
  end

  def sendable_recipients?
    email_campaign_recipients.exists? && EmailCampaigns::PreflightDecision.new.campaign_allowed?(self)
  end

  def sender_ready?
    if direct_inbox?
      sender_inbox.present? && sender_inbox.channel.is_a?(Channel::Email)
    else
      sender_identity&.usable?
    end
  end

  # Don't let an empty campaign go out: require rendered HTML or MJML source before sending.
  def body_present?
    body_html.present? || body_mjml.present?
  end

  def terminal?
    sent? || canceled? || failed?
  end

  def mark_sending!
    with_delivery_lock do
      next false unless scheduled? && !recipient_import_active?

      update!(status: :sending)
    end
  end

  # All delivery mutations enter account -> state -> campaign before assigning
  # attributes. Do not wrap this in a child lock or call it from a save callback.
  def with_delivery_lock(&)
    EmailCampaigns::Reputation::Admission.new(self).with_campaign_locks(&)
  end

  # Atomic draft/scheduled -> sending transition. Returns true only for the caller
  # whose UPDATE actually flips the row, closing the send_now TOCTOU window.
  def claim_for_sending!
    with_delivery_lock do
      return false unless sendable?

      update!(status: :sending)
      true
    end
  end

  def schedule!(scheduled_at:)
    with_delivery_lock do
      return false unless sendable?

      update!(status: :scheduled, scheduled_at: scheduled_at)
    end
  end

  # Includes ambiguous claims/failures whose provider feedback may still arrive later.
  def delivery_history?
    recipients = email_campaign_recipients
    recipients.where.not(sent_at: nil).or(recipients.where.not(status: %i[pending suppressed])).exists? || email_events.exists?
  end

  def recipient_import_active?
    email_campaign_imports.active.exists?
  end

  def pause!
    with_delivery_lock do
      next unless sending? || scheduled?

      update!(status: :paused, hygiene_pause_reason: nil, pause_reason: { kind: 'manual', code: 'manual_pause' })
    end
  end

  def resume!(actor: nil)
    return false unless reload.paused?

    ensure_resume_eligible!
    # Reputation collects outside all campaign/account locks. Publication and the
    # campaign transition commit together; a failed final hygiene check rolls back release.
    result = EmailCampaigns::Guardrail.resume!(account, actor: actor, delivery_mode: delivery_mode) do
      with_lock do
        ensure_resume_eligible!
        update!(status: :sending, hygiene_pause_reason: nil, pause_reason: {}, last_error: nil)
      end
    end
    raise CustomExceptions::EmailReputationBlocked, result unless result[:resume_allowed]

    ActiveRecord.after_all_transactions_commit { EmailCampaigns::DeliveryJob.perform_later(id) } if EmailCampaigns::Config.enabled?
    true
  end

  def cancel!
    with_delivery_lock do
      return false if recipient_import_active?
      return true if sent? || failed?

      update!(status: :canceled)
    end
    # Cancellation fences new claims first. Cleanup is repeatable, with bounded
    # batches so a large list cannot hold the account write lock for the whole list.
    email_campaign_recipients.pending.in_batches(of: CANCELLATION_BATCH_SIZE) do |batch|
      with_delivery_lock do
        batch.update_all(status: EmailCampaignRecipient.statuses[:suppressed], updated_at: Time.current)
      end
    end
    refresh_counters!
  end

  def finalize!
    with_delivery_lock do
      return unless sending?
      return if recipient_import_active? || email_campaign_recipients.pending.exists?
      # Another worker may own an optimistic claim but not have reached the provider.
      # An ambiguous claim without a persisted receipt requires operator review.
      return if email_campaign_recipients.sent.exists?(sent_at: nil)

      update!(status: :sent, sent_at: Time.current)
    end
    refresh_counters!
  end

  # ---- geração de e-mail por IA (assíncrona/durável) ----
  # Cada geração ganha um TOKEN único. Toda transição posterior (attach/succeed/fail) só vale se o
  # token ainda for o ativo E o status ainda for processing — assim um job velho (clique duplo / nova
  # geração que substituiu esta) NÃO sobrescreve nem derruba a geração atual (achados Codex #1/#2/#3).
  # Retorna o token para o SubmitJob/PollJob carregarem.
  def ai_begin!
    token = SecureRandom.hex(16)
    update_columns(ai_status: self.class.ai_statuses[:processing], ai_generation_token: token,
                   ai_provider_response_id: nil, ai_error: nil,
                   ai_requested_at: Time.current, ai_completed_at: nil, updated_at: Time.current)
    token
  end

  def ai_attach_response!(token, response_id)
    ai_guarded_update(token, ai_provider_response_id: response_id)
  end

  # Grava o conteúdo gerado no rascunho (mjml; o body_html é compilado no editor ao salvar, igual ao
  # fluxo síncrono atual) e marca pronto. Retorna true só se ESTA geração ainda era a ativa.
  def ai_succeed!(token, subject:, preheader:, body_mjml:, subject_variants:)
    ai_guarded_update(
      token,
      subject: subject.to_s.strip.presence || self.subject,
      preheader: preheader.to_s.presence,
      body_mjml: body_mjml,
      ai_subject_variants: Array(subject_variants),
      ai_status: self.class.ai_statuses[:ready], ai_error: nil, ai_completed_at: Time.current
    )
  end

  def ai_fail!(token, message)
    ai_guarded_update(token, ai_status: self.class.ai_statuses[:failed],
                             ai_error: message.to_s.truncate(500), ai_completed_at: Time.current)
  end

  # Persisted `sent_at` is the durable evidence that a transport was accepted.
  # Recipient status can later move to delivered/bounced/complained/unsubscribed or
  # even provider-suppressed; those transitions must never make "Enviados" decrease.
  def refresh_counters!
    # A caller may still own import/recipient locks in an outer transaction.
    # Both aggregation and parent locking must wait for that transaction's commit.
    ActiveRecord.after_all_transactions_commit do
      counters = counter_attributes
      with_delivery_lock { update_columns(counters) }
    end
  end

  private

  def counter_attributes
    counts = email_campaign_recipients.group(:status).count
    ev = event_counters
    {
      recipients_count: counts.values.sum,
      sent_count: email_campaign_recipients.where.not(sent_at: nil).count,
      failed_count: count_for(counts, 'failed'),
      suppressed_count: count_for(counts, 'suppressed'),
      delivered_count: ev[:delivered],
      opened_count: ev[:opened],
      clicked_count: ev[:clicked],
      bounced_count: ev[:bounced],
      complained_count: ev[:complained],
      unsubscribed_count: ev[:unsubscribed],
      updated_at: Time.current
    }
  end

  def ensure_resume_eligible!
    code = if !paused?
             'campaign_not_paused'
           elsif recipient_import_active?
             'recipient_import_active'
           elsif !EmailCampaigns::PreflightDecision.new.campaign_allowed?(self)
             EmailCampaigns::PreflightDecision::PAUSE_REASON
           end
    return unless code

    raise CustomExceptions::EmailReputationBlocked.new(
      resume_allowed: false, protection: { kind: 'hygiene', code: code, overridable: false }
    )
  end

  # Backstop sanitization: run the same MJML cleaner used on AI output over any body_mjml that
  # changes (direct MJML edits, video blocks, hand-pasted markup) so it isn't limited to the AI
  # path. The cleaner is idempotent and only runs when body_mjml actually changed.
  def sanitize_body_mjml
    self.body_mjml = EmailCampaigns::Ai::Sanitizer.new(body_mjml).perform
  end

  def count_for(counts, name)
    counts.fetch(name, counts.fetch(EmailCampaignRecipient.statuses[name], 0))
  end

  # Escreve só se a geração identificada por `token` ainda for a ativa e ainda estiver processing.
  # update_all atômico fecha a janela entre checagem e escrita. Retorna true se ganhou (1 linha).
  def ai_guarded_update(token, attrs)
    return false if token.blank?

    rows = EmailCampaign.where(id: id, ai_generation_token: token, ai_status: self.class.ai_statuses[:processing])
                        .update_all(attrs.merge(updated_at: Time.current))
    reload if rows.positive?
    rows.positive?
  end

  # Event-derived counters. Opens are deduped per recipient (Apple MPP inflation — the report
  # labels opens APPROXIMATE); click/bounce/unsubscribe are raw event counts.
  # Complaint prevention notifications are not new recipient spam reports.
  def event_counters
    by_type = email_events.group(:event_type).count
    {
      delivered: type_count(by_type, :delivered),
      opened: email_events.opens.distinct.count(:recipient_id),
      clicked: type_count(by_type, :click),
      bounced: type_count(by_type, :bounce),
      complained: email_events.where(EmailCampaigns::ComplaintClassifier::REAL_COMPLAINT_SQL).count,
      unsubscribed: type_count(by_type, :unsubscribe)
    }
  end

  def type_count(by_type, name)
    by_type.fetch(name.to_s, by_type.fetch(EmailEvent.event_types[name.to_s], 0))
  end

  def set_direct_from_email
    self.from_email = sender_inbox&.channel.try(:email).to_s.strip.downcase.presence
  end

  def sender_identity_must_belong_to_account
    return if sender_identity.nil?
    return if sender_identity.account_id == account_id

    errors.add(:sender_identity_id, 'must belong to the same account')
  end

  def sender_inbox_must_belong_to_account
    return if sender_inbox.nil?
    return if sender_inbox.account_id == account_id

    errors.add(:sender_inbox_id, 'must belong to the same account')
  end

  def sender_present_for_mode
    if direct_inbox?
      errors.add(:sender_inbox_id, 'is required for direct sending') if sender_inbox.nil?
    elsif sender_identity.nil?
      errors.add(:sender_identity_id, 'is required')
    end
  end

  def reply_to_format
    errors.add(:reply_to, 'is invalid') unless reply_to.match?(EMAIL_REGEX)
  end

  def from_email_matches_sender_domain
    domain = sender_identity&.domain
    return if domain.present? && from_email.match?(EMAIL_REGEX) && from_email.downcase.end_with?("@#{domain}")

    errors.add(:from_email, 'from_email_domain_mismatch')
  end
end
