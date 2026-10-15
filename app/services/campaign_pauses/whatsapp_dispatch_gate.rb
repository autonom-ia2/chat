# Template check before a WhatsApp Oficial campaign goes out (#1329, épico #1320). Prepended into
# Whatsapp::OneoffCampaignService by config/initializers/campaign_pauses.rb, after the campaign
# journey modules, so it is the outermost `perform` and runs before any recipient is created:
#   CampaignPauses::WhatsappDispatchGate → CampaignJourney::WhatsappOneoffRecipients →
#   CampaignJourney::AudienceContacts → Enterprise::Whatsapp::OneoffCampaignService → Chatwoot
# When the template no longer matches (Whatsapp::Templates::DispatchCheck) nobody receives anything:
# the campaign gets an open CampaignPause with the reason and goes back to `active`. Otherwise `super`
# runs untouched — opt-out (chat#737), phone or BSUID destination and the authentication guard
# (Whatsapp::AuthenticationTemplateGuard) stay where they are.
# #1418: a template with catalog products also checks that each chosen product is still in the inbox catalog and for
# sale (Whatsapp::Templates::DispatchProducts); otherwise the whole campaign pauses with the product name.
# Every WhatsApp Cloud one-off campaign with template_params goes through the check. A check that
# breaks never sends blind and never leaves the campaign stuck in `processing`: it pauses by the system.
#
# Check and send read the same template (#1382). The check asks Meta; the send
# (Whatsapp::TemplateProcessorService) reads the inbox list. When Meta answered with the approved
# template, that item is written into the campaign inbox's list (Whatsapp::Templates::ChannelList,
# locked, only that entry), so a list still saying PAUSED, a sibling inbox of the same WABA not synced
# yet or a list cut by a failed sync no longer make every send go out without variables. If the send
# would still not find the template, the campaign pauses by the system with `template_missing`.
module CampaignPauses::WhatsappDispatchGate
  def perform
    return super unless template_check_applies?

    verdict = template_verdict
    return super if verdict.ok?

    Rails.logger.warn "[CampaignPauses] campaign=#{campaign.id} paused reason=#{verdict.reason_code} source=#{verdict.source}"
    CampaignPauses::Pauser.new(campaign, source: verdict.source, reason_code: verdict.reason_code, details: verdict.details).perform
  end

  private

  def template_check_applies?
    campaign.one_off? && !campaign.completed? && campaign.template_params.present? && whatsapp_cloud_channel? &&
      campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def template_verdict
    verdict = Whatsapp::Templates::DispatchCheck.new(campaign, channel: channel).call
    verdict = send_list_verdict(verdict) if verdict.ok?
    verdict = header_media_verdict(verdict) if verdict.ok?
    verdict = send_extras_verdict(verdict) if verdict.ok?
    verdict.ok? ? products_verdict(verdict) : verdict
  rescue StandardError => e
    Rails.logger.error "[CampaignPauses] campaign=#{campaign.id} template check failed: #{e.class.name}"
    Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: 'template_unverifiable', source: 'system',
                                                    details: { error_class: e.class.name })
  end

  # `channel` is the object the send reads: ChannelList locks and reloads it, so the send sees the written item.
  def send_list_verdict(verdict)
    keep_meta_version(verdict.template) if verdict.details[:lookup_source] == Whatsapp::Templates::DispatchCheck::META
    return verdict if Whatsapp::TemplateProcessorService.new(channel: channel, template_params: campaign.template_params).template_in_list?

    Whatsapp::Templates::DispatchCheck::Verdict.new(
      reason_code: 'template_missing', source: 'system',
      details: verdict.details.slice(:template_name, :language, :lookup_source).merge(stage: 'inbox_list')
    )
  end

  # Media header without a typed link (#1382): the file chosen in the campaign (#1465) or else the template's saved file,
  # linked once per run, goes to every send.
  def header_media_verdict(verdict)
    return verdict unless Whatsapp::Templates::HeaderMedia.media_type(verdict.template)

    header = campaign.template_params.to_h.dig('processed_params', 'header')
    return verdict if header.is_a?(Hash) && header['media_url'].present?

    @header_media = Whatsapp::Templates::HeaderMedia.dispatch_media(header, inbox, verdict.template)
    return verdict if @header_media

    Whatsapp::Templates::DispatchCheck::Verdict.new(
      reason_code: 'template_media_missing', source: 'template', details: verdict.details.slice(:template_name, :language, :lookup_source)
    )
  end

  # #1334: the saved file of each carousel card and the campaign flow_token, built once per run (Whatsapp::Templates::SendParams).
  def send_extras_verdict(verdict)
    processed = campaign.template_params.to_h['processed_params']
    extras = Whatsapp::Templates::SendParams.dispatch_extras(processed, template: verdict.template, inbox: inbox, campaign: campaign)
    @send_extras = extras.presence
    return verdict if extras

    Whatsapp::Templates::DispatchCheck::Verdict.new(
      reason_code: 'template_media_missing', source: 'template', details: verdict.details.slice(:template_name, :language, :lookup_source)
    )
  end

  # #1418: each chosen product still in the inbox catalog and for sale; the catalog goes to every send.
  # Sem a flag `whatsapp_campaign_products` (desligada depois de a campanha ser criada), a campanha de produtos para
  # inteira com motivo próprio: nada sai.
  def products_verdict(verdict)
    return products_disabled_verdict(verdict) if products_disabled?(verdict.template)

    processed = campaign.template_params.to_h['processed_params']
    check = Whatsapp::Templates::DispatchProducts.new(inbox: inbox, template: verdict.template, processed: processed).call
    @product_catalog_id = check.catalog_id
    return verdict if check.ok?

    Whatsapp::Templates::DispatchCheck::Verdict.new(
      reason_code: check.reason_code, source: 'template',
      details: verdict.details.slice(:template_name, :language, :lookup_source).merge(check.details)
    )
  end

  def products_disabled?(template)
    Whatsapp::Templates::ProductParams.kind(template).present? && !campaign.account.feature_enabled?('whatsapp_campaign_products')
  end

  def products_disabled_verdict(verdict)
    Whatsapp::Templates::DispatchCheck::Verdict.new(
      reason_code: 'template_products_disabled', source: 'template',
      details: verdict.details.slice(:template_name, :language, :lookup_source)
    )
  end

  def process_liquid_template_params(contact)
    params = super
    return params unless params && (@header_media || @send_extras || @product_catalog_id)

    params.merge('processed_params' => with_dispatch_extras(params['processed_params'].to_h))
  end

  def with_dispatch_extras(processed)
    processed = processed.merge('header' => processed['header'].to_h.except('media_blob').merge(@header_media)) if @header_media
    processed = Whatsapp::Templates::SendParams.apply_extras(processed, @send_extras) if @send_extras
    return processed unless @product_catalog_id

    processed.merge('products' => processed['products'].to_h.merge('catalog_id' => @product_catalog_id))
  end

  def keep_meta_version(template)
    # Sem parameter_format (a Graph recusou o campo), só atualiza a entrada que o sync já gravou: o envio precisa do formato.
    Whatsapp::Templates::ChannelList.upsert!(channel, template, merge: true, only_existing: !template.key?('parameter_format'))
  rescue StandardError => e
    # The send-list check right after decides: the item may already be there from the sync.
    Rails.logger.error "[CampaignPauses] campaign=#{campaign.id} meta template not kept: #{e.class.name}"
  end
end
