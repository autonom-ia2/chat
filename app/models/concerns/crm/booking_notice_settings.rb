# Avisos no WhatsApp da página de agendamento nova (#1192, F2-A): caixa que manda os avisos, jogo de avisos pronto
# (J5-A8), modelos aprovados por aviso e prazo para o cliente cancelar ou remarcar (J5-A3).
#
# Caixa de avisos aceita: WhatsApp oficial (Cloud ou 360dialog) e canal API de WhatsApp (WAHA ou API de campanhas).
# Modelos: `{ "<aviso>": { "name": "...", "language": "pt_BR" } }` para o WhatsApp oficial e `{ "<aviso>": { "id": 5 } }`
# (modelo do canal API) para o canal API. Modelo da Meta que já está na lista sincronizada da caixa precisa levar o
# `{{3}}` (link de gestão, onde fica o "Parar avisos", J2-A9/RA-18) e pedir só o que o aviso preenche (`{{1}}`..`{{3}}` no
# corpo, topo sem variável nem mídia, botão sem link variável); o envio confere de novo (`template_without_link`,
# `template_unsupported`).
module Crm::BookingNoticeSettings
  extend ActiveSupport::Concern

  # Jogos de avisos prontos: o admin escolhe um, sem digitar horário.
  PRESETS = {
    'standard' => %w[booked day_before hour_before],
    'light' => %w[booked hour_before],
    'minimal' => %w[booked]
  }.freeze
  MAX_CANCEL_UNTIL_MINUTES = 7 * 24 * 60
  MAX_TEMPLATE_TEXT = 512

  included do
    belongs_to :notice_inbox, class_name: 'Inbox', optional: true

    before_validation :normalize_notice_templates
    validates :notice_preset, inclusion: { in: PRESETS.keys }
    validates :cancel_until_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0,
                                                     less_than_or_equal_to: MAX_CANCEL_UNTIL_MINUTES }
    validate :notice_inbox_must_be_usable
    validate :notice_templates_must_be_sane
    validate :notice_templates_must_carry_link
    validate :notice_templates_must_be_fillable
  end

  class_methods do
    # Caixa que pode mandar aviso: WhatsApp oficial, ou canal API de WhatsApp (WAHA ou API de campanhas).
    def notice_inbox_supported?(inbox)
      notice_channel_kind(inbox).present?
    end

    # 'whatsapp' (Cloud/360dialog: precisa de modelo aprovado fora da janela), 'waha' (só dentro da janela de 24 h
    # aberta pelo cliente) ou 'api' (canal API de campanhas: modelo do canal por id fora da janela). nil: não serve.
    def notice_channel_kind(inbox)
      channel = inbox&.channel
      return 'whatsapp' if channel.is_a?(Channel::Whatsapp)
      return unless channel.is_a?(Channel::Api)
      return 'waha' if channel.waha_provider? || channel.whatsapp_api_provider == 'waha'

      'api' if channel.whatsapp_api_campaign_channel?
    end
  end

  def notice_kinds
    PRESETS.fetch(notice_preset, PRESETS['standard'])
  end

  # A caixa de avisos existe, é desta conta e é de um canal que manda aviso.
  def notices_usable?
    notice_inbox.present? && notice_inbox.account_id == account_id && self.class.notice_inbox_supported?(notice_inbox)
  end

  def notice_template(kind)
    notice_templates.to_h[kind.to_s].presence
  end

  private

  # Formulário manda o id do modelo como texto ("5"): só converte o que é inteiro de verdade; o resto a validação
  # recusa.
  def normalize_notice_templates
    return unless notice_templates.is_a?(Hash)

    self.notice_templates = notice_templates.deep_stringify_keys.transform_values do |value|
      next value unless value.is_a?(Hash) && value['id'].is_a?(String)

      value.merge('id' => Integer(value['id'], exception: false) || value['id'])
    end
  end

  def notice_inbox_must_be_usable
    return if notice_inbox_id.blank?
    return errors.add(:notice_inbox, 'must belong to the same account') if notice_inbox.blank? || notice_inbox.account_id != account_id

    errors.add(:notice_inbox, 'must be a WhatsApp inbox') unless self.class.notice_inbox_supported?(notice_inbox)
  end

  def notice_templates_must_be_sane
    templates = notice_templates
    return errors.add(:notice_templates, 'must be an object') unless templates.is_a?(Hash)
    return errors.add(:notice_templates, 'unknown notice') unless (templates.keys - Crm::MeetingNotice::KINDS).empty?

    errors.add(:notice_templates, 'invalid template') unless templates.values.all? { |value| valid_notice_template?(value) }
  end

  # Só confere o que mudou (o modelo pode mudar na Meta depois; o envio confere de novo) e só modelo já sincronizado.
  def notice_templates_must_carry_link
    missing = synced_notice_templates.reject { |_kind, template| carries_link?(template) }.keys
    errors.add(:notice_templates, "must include {{3}} (manage link): #{missing.join(', ')}") if missing.any?
  end

  # O aviso só preenche {{1}}..{{3}} do corpo: o que pede mais a Meta recusaria no envio (`Route.fillable_template?`).
  def notice_templates_must_be_fillable
    route = Crm::BookingV2::Notices::Route
    unfillable = synced_notice_templates.select { |_kind, template| carries_link?(template) && !route.fillable_template?(template) }.keys
    errors.add(:notice_templates, "must only use {{1}}, {{2}} and {{3}}: #{unfillable.join(', ')}") if unfillable.any?
  end

  # Modelos da Meta configurados que já estão na lista sincronizada da caixa, só quando modelos ou caixa mudam.
  def synced_notice_templates
    return {} unless notice_templates.is_a?(Hash) && notice_inbox&.channel.is_a?(Channel::Whatsapp)
    return {} unless notice_templates_or_inbox_changing?

    notice_templates.transform_values { |configured| synced_notice_template(configured) }.compact
  end

  def carries_link?(template)
    route = Crm::BookingV2::Notices::Route
    route.native_body(template).include?(route::LINK_PLACEHOLDER)
  end

  def notice_templates_or_inbox_changing?
    will_save_change_to_notice_templates? || will_save_change_to_notice_inbox_id?
  end

  def synced_notice_template(configured)
    Crm::BookingV2::Notices::Route.synced_template(notice_inbox, configured) if configured.is_a?(Hash)
  end

  def valid_notice_template?(value)
    return false unless value.is_a?(Hash) && (value.keys - %w[name language id]).empty?
    return value['id'].is_a?(Integer) && value['id'].positive? if value.key?('id')

    %w[name language].all? { |key| template_text?(value[key]) }
  end

  def template_text?(text)
    text.is_a?(String) && text.strip.present? && text.length <= MAX_TEMPLATE_TEXT
  end
end
