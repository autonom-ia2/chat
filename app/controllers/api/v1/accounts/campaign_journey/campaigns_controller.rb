# Campaign journey: creates a campaign that sends to a saved audience. Channels:
#   whatsapp_cloud — WhatsApp Oficial (#1005, docs/campaigns/publicos/api-1005.md);
#   whatsapp_api   — WhatsApp API (#999, docs/campaigns/publicos/api-999.md);
#   email          — e-mail draft for the existing builder flow (#999, api-999.md);
#   sms            — SMS, Twilio SMS or Bandwidth (#1004, docs/campaigns/publicos/api-1004.md).
# CAMPAIGN_JOURNEY_ENABLED off → 404; campaign_manage required (CampaignPolicy#create?), otherwise 401. Every channel but
# e-mail sends or schedules right away, so it also needs campaign_send (CampaignPolicy#send_campaign?, #1898). The e-mail
# one is a draft: sending it goes through the e-mail campaign screen (EmailCampaignPolicy#send_now?).
# `draft_id` (#1898): the server draft this campaign came from. Except for e-mail, it is claimed (deleted) in the same
# transaction that creates the campaign: two tabs or two people sending the same draft create one campaign, and the
# other gets 422 draft_gone; a refused campaign rolls the claim back and the draft stays. For e-mail it is linked to the
# new e-mail draft and goes when that e-mail is sent or scheduled (CampaignJourney::DraftCleanup).
# `campaign.duas_versoes` (#3099): { criterio, divisao, espera_horas, segunda } turns on the two versions of the message
# (WhatsApp Oficial, SMS, WhatsApp API); `recipients_count` is then who receives now (the test). E-mail sets them in
# PUT email_medicoes.
# `campaign.melhor_horario` (#3101): true sends to each person at their best hour (Autonomia::MelhorHorario), saved in
# the same transaction as the campaign, before any send job sees it.
# `campaign.reenvio_quem`, `reenvio_dias`, `reenvio_mensagem` (#3101): the second message to who did not reply
# (CampaignJourney::Reenvio), same transaction; refused with 422 and the code (reenvio_*), and then the campaign is not
# created. E-mail sets them in PUT email_medicoes.
class Api::V1::Accounts::CampaignJourney::CampaignsController < Api::V1::Accounts::BaseController
  CHANNELS = %w[whatsapp_cloud whatsapp_api email sms].freeze

  before_action :ensure_campaign_journey_enabled
  before_action :check_authorization

  def create
    # Contact imports (#1006) are never audiences: campaign_flows keeps them out.
    campaign_import = Current.account.campaign_imports.campaign_flows.find(params.require(:campaign_import_id))
    campaign = with_claimed_draft { create_for(params[:channel].to_s, campaign_import) }
    render json: payload_for(campaign)
  rescue ::CampaignJourney::WhatsappCampaignCreator::Error, ::CampaignJourney::CreatorError => e
    render json: { error: e.message, code: e.code, details: e.details }.compact, status: :unprocessable_entity
  rescue ::CampaignJourney::Reenvio::Invalido => e
    render json: { error: 'The second message cannot be used', code: e.code }, status: :unprocessable_entity
  end

  private

  # #3101: except for e-mail, the campaign, its audience link, the claimed draft and its sending options (melhor_horario,
  # reenvio) commit together, and a refused second message rolls the campaign back. Nothing sends before that commit:
  # WhatsApp Oficial and SMS campaigns are picked by TriggerScheduledItemsJob, and the WhatsApp API creator enqueues its
  # scheduler only after the outermost commit (WhatsappApiCampaigns::Creator#enqueue_scheduler_after_commit). The
  # e-mail one is a draft that sends nothing on create. The payload is built after the commit: Campaign#display_id comes
  # from the database in an after_commit (Campaign#set_display_id).
  def with_claimed_draft(&)
    return yield if email_channel?

    draft_id = ::CampaignJourney::DraftCleanup.single_id(params[:draft_id])
    return ActiveRecord::Base.transaction(&) if draft_id.nil?

    ActiveRecord::Base.transaction do
      claimed = CampaignJourneyDraft.where(account_id: Current.account.id, id: draft_id).delete_all == 1
      raise ::CampaignJourney::CreatorError.new('draft_gone', 'This draft was already sent') unless claimed

      yield
    end
  end

  def create_for(channel, campaign_import)
    case channel
    when ::CampaignJourney::WhatsappApiCampaignCreator::CHANNEL then create_whatsapp_api(campaign_import)
    when ::CampaignJourney::EmailCampaignCreator::CHANNEL then create_email(campaign_import)
    when ::CampaignJourney::WhatsappCampaignCreator::CHANNEL then create_whatsapp_cloud(campaign_import)
    when ::CampaignJourney::SmsCampaignCreator::CHANNEL then create_sms(campaign_import)
    else raise ::CampaignJourney::CreatorError.new('unsupported_channel', "Channel must be one of: #{CHANNELS.join(', ')}")
    end
  end

  def create_whatsapp_cloud(campaign_import)
    campaign = ::CampaignJourney::WhatsappCampaignCreator.new(
      account: Current.account, campaign_import: campaign_import, channel: params[:channel], attributes: whatsapp_cloud_params
    ).perform
    guardar_opcoes_de_envio(campaign)
    campaign
  end

  def create_sms(campaign_import)
    campaign = ::CampaignJourney::SmsCampaignCreator.new(
      account: Current.account, campaign_import: campaign_import, channel: params[:channel], attributes: whatsapp_cloud_params
    ).perform
    guardar_opcoes_de_envio(campaign)
    campaign
  end

  def create_whatsapp_api(campaign_import)
    campaign = ::CampaignJourney::WhatsappApiCampaignCreator.new(
      account: Current.account, user: Current.user, campaign_import: campaign_import, params: params.require(:campaign)
    ).perform
    guardar_opcoes_de_envio(campaign)
    campaign
  end

  def create_email(campaign_import)
    campaign = ::CampaignJourney::EmailCampaignCreator.new(
      account: Current.account, campaign_import: campaign_import, attributes: email_params
    ).perform.reload
    guardar_opcoes_de_envio(campaign)
    ::CampaignJourney::DraftCleanup.link_email(Current.account, draft_id: params[:draft_id], email_campaign: campaign)
    campaign
  end

  # The journey channel of the campaign just created (CampaignJourney::Reenvio.canal_de).
  def payload_for(campaign)
    case ::CampaignJourney::Reenvio.canal_de(campaign)
    when ::CampaignJourney::WhatsappApiCampaignCreator::CHANNEL then whatsapp_api_payload(campaign)
    when ::CampaignJourney::EmailCampaignCreator::CHANNEL then email_payload(campaign)
    when ::CampaignJourney::SmsCampaignCreator::CHANNEL then sms_payload(campaign)
    else whatsapp_cloud_payload(campaign)
    end
  end

  def whatsapp_cloud_payload(campaign)
    link = CampaignAudienceLink.for_campaign(campaign)
    {
      id: campaign.id, display_id: campaign.display_id, title: campaign.title,
      channel: ::CampaignJourney::WhatsappCampaignCreator::CHANNEL, scheduled_at: campaign.scheduled_at,
      recipients_count: ::CampaignJourney::AudienceContacts.contacts_for(link, channel: :whatsapp).count
    }
  end

  def sms_payload(campaign)
    link = CampaignAudienceLink.for_campaign(campaign)
    {
      id: campaign.id, display_id: campaign.display_id, title: campaign.title, channel: ::CampaignJourney::SmsCampaignCreator::CHANNEL,
      scheduled_at: campaign.scheduled_at, inbox_id: campaign.inbox_id,
      recipients_count: ::CampaignJourney::AudienceContacts.contacts_for(link, channel: :sms).count,
      message_stats: ::CampaignJourney::SmsSegments.count(campaign.message)
    }
  end

  def whatsapp_api_payload(campaign)
    link = CampaignAudienceLink.for_campaign(campaign)
    {
      id: campaign.id, title: campaign.title, channel: ::CampaignJourney::WhatsappApiCampaignCreator::CHANNEL,
      scheduled_at: campaign.scheduled_at, inbox_id: campaign.inbox_id,
      recipients_count: ::CampaignJourney::AudienceContacts.contacts_for(link, channel: :whatsapp).count
    }
  end

  def email_payload(campaign)
    {
      id: campaign.id, title: campaign.name, channel: ::CampaignJourney::EmailCampaignCreator::CHANNEL, status: campaign.status,
      delivery_mode: campaign.delivery_mode, reply_to_inbox_id: campaign.reply_to_inbox_id,
      recipients_count: campaign.email_campaign_recipients.pending.count,
      suppressed_count: campaign.email_campaign_recipients.suppressed.count
    }
  end

  def guardar_opcoes_de_envio(campaign)
    ::Autonomia::MelhorHorario.guardar!(campaign, ActiveModel::Type::Boolean.new.cast(params.dig(:campaign, :melhor_horario)) || false)
    ::CampaignJourney::Reenvio.guardar!(campaign, reenvio_params) unless email_channel?
  end

  def reenvio_params
    params.require(:campaign).permit(:reenvio_quem, :reenvio_dias, reenvio_mensagem: {}).to_h
  end

  def email_channel?
    params[:channel].to_s == ::CampaignJourney::EmailCampaignCreator::CHANNEL
  end

  def check_authorization
    authorize(Campaign, :create?)
    authorize(Campaign, :send_campaign?) unless email_channel?
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end

  # template_params: same shape Api::V1::Accounts::CampaignsController accepts. SMS uses title,
  # inbox_id, scheduled_at, message and variable_defaults.
  def whatsapp_cloud_params
    params.require(:campaign).permit(
      :title, :inbox_id, :scheduled_at, :message, :free_text, :janela_de_compra_dias, :grupo_de_controle_pct,
      template_params: {}, variable_bindings: {}, variable_defaults: {},
      duas_versoes: [:criterio, :divisao, :espera_horas, { segunda: {} }]
    ).to_h
  end

  def email_params
    params.require(:campaign).permit(
      :title, :delivery_mode, :sender_identity_id, :sender_inbox_id, :from_name, :from_email, :reply_to_inbox_id, :subject, :preheader
    ).to_h
  end
end
