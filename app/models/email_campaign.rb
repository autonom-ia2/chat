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
    (draft? || scheduled?) && subject.present? && body_html.present? && sender_ready? &&
      email_campaign_recipients.exists?
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
    update!(status: :sending)
  end

  # Atomic draft/scheduled -> sending transition. Returns true only for the caller
  # whose UPDATE actually flips the row, closing the send_now TOCTOU window.
  def claim_for_sending!
    claimed = EmailCampaign.where(id: id, status: [self.class.statuses[:draft], self.class.statuses[:scheduled]])
                           .update_all(status: self.class.statuses[:sending], updated_at: Time.current)
    return false if claimed.zero?

    reload
    true
  end

  def pause!
    return unless sending? || scheduled?

    update!(status: :paused)
  end

  def resume!
    return unless paused?

    update!(status: :sending)
    EmailCampaigns::DeliveryJob.perform_later(id) if EmailCampaigns::Config.enabled?
  end

  def cancel!
    return if terminal?

    with_lock do
      update!(status: :canceled)
      email_campaign_recipients.where(status: :pending)
                               .update_all(status: EmailCampaignRecipient.statuses[:suppressed],
                                           updated_at: Time.current)
      refresh_counters!
    end
  end

  def finalize!
    refresh_counters!
    update!(status: :sent, sent_at: Time.current)
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

  # Recipients that were successfully dispatched. A recipient leaves the literal
  # :sent bucket as SNS events arrive (-> :delivered / :opened / :clicked /
  # :bounced / :complained / :unsubscribed), so counting only 'sent' made the
  # "Enviados" total drop back to 0 once delivery was confirmed. Everything except
  # pending / failed / suppressed means the email was sent.
  NON_DISPATCHED_STATUSES = %w[pending failed suppressed].freeze

  def refresh_counters!
    counts = email_campaign_recipients.group(:status).count
    ev = event_counters
    update_columns(
      recipients_count: counts.values.sum,
      sent_count: counts.values.sum -
        NON_DISPATCHED_STATUSES.sum { |s| count_for(counts, s) },
      failed_count: count_for(counts, 'failed'),
      suppressed_count: count_for(counts, 'suppressed'),
      delivered_count: ev[:delivered],
      opened_count: ev[:opened],
      clicked_count: ev[:clicked],
      bounced_count: ev[:bounced],
      complained_count: ev[:complained],
      unsubscribed_count: ev[:unsubscribed],
      updated_at: Time.current
    )
  end

  private

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
  # labels opens APPROXIMATE); click/bounce/complaint/unsubscribe are raw event counts.
  def event_counters
    by_type = email_events.group(:event_type).count
    {
      delivered: type_count(by_type, :delivered),
      opened: email_events.opens.distinct.count(:recipient_id),
      clicked: type_count(by_type, :click),
      bounced: type_count(by_type, :bounce),
      complained: type_count(by_type, :complaint),
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
