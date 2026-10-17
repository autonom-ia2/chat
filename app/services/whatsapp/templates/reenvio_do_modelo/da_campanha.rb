# A mensagem de campanha gravada na conversa (`CampaignJourney::SentMessageRecorder`) só guarda `campaign_id` e o nome do
# modelo: os parâmetros daquela pessoa nunca ficaram na mensagem. Aqui eles são remontados como o disparo montou
# (`Whatsapp::OneoffCampaignService` com `CampaignJourney::WhatsappOneoffRecipients` e
# `CampaignPauses::WhatsappDispatchGate`), sem tocar no destinatário nem na campanha:
# 1. o destinatário pelo id da Meta da mensagem (`campaign_recipients.source_id`);
# 2. o Liquid da campanha com o contato dele (`Whatsapp::LiquidTemplateProcessorService`);
# 3. as variáveis do público, quando a campanha tem (`CampaignJourney::VariableBindings` + `TemplateVariableKeys`);
# 4. o modelo gravado na mensagem (`campaign_template_name`): se a campanha trocou de modelo depois, vai o que a pessoa
#    recebeu (a conferência na caixa de destino decide se ele ainda existe e se os valores cabem);
#    sem conferir o texto: contato que mudou de nome vai com o nome atual, como num disparo novo (ajudar, não travar);
# 5. `com_extras`, na caixa de destino: o arquivo do topo, os cartões do carrossel, o flow_token e o catálogo, que o
#    disparo acrescenta em cada envio e nunca ficam guardados (o link do arquivo expira).
class Whatsapp::Templates::ReenvioDoModelo::DaCampanha
  CAMPOS = Whatsapp::Templates::ReenvioDoModelo::CAMPOS

  attr_reader :motivo

  def initialize(message)
    @message = message
    @atributos = message.additional_attributes.to_h
    @motivo = 'sem_parametros'
  end

  # template_params da pessoa (name, language, category, processed_params) ou nil, com `motivo`.
  def parametros
    return nao_e_modelo if @atributos['campaign_free_text'].present?

    @campanha = Campaign.find_by(id: @atributos['campaign_id'], account_id: @message.account_id)
    return nao_e_modelo if @campanha.nil? || @campanha.template_params.blank?

    contato = destinatario&.contact
    return if contato.nil?

    montar(contato)
  end

  # Como `CampaignPauses::WhatsappDispatchGate#with_dispatch_extras`, com o modelo e a caixa de destino. nil com `motivo`.
  def com_extras(params, template:, inbox:)
    processed = topo(params['processed_params'].to_h, template, inbox)
    return midia_indisponivel if processed.nil?

    extras = Whatsapp::Templates::SendParams.dispatch_extras(processed, template: template, inbox: inbox, campaign: @campanha)
    return midia_indisponivel if extras.nil?

    processed = Whatsapp::Templates::SendParams.apply_extras(processed, extras) if extras.present?
    processed = produtos(processed, template, inbox)
    processed && params.merge('processed_params' => processed)
  end

  private

  # Arquivo do topo ou de um cartão que sumiu (o disparo pausaria com `template_media_missing`).
  def midia_indisponivel
    @motivo = 'midia_indisponivel'
    nil
  end

  def nao_e_modelo
    @motivo = 'nao_e_modelo'
    nil
  end

  def destinatario
    return if @message.source_id.blank?

    CampaignRecipient.find_by(campaign_id: @campanha.id, account_id: @message.account_id, source_id: @message.source_id)
  end

  def montar(contato)
    params = Whatsapp::LiquidTemplateProcessorService.new(campaign: @campanha, contact: contato)
                                                     .process_template_params(@campanha.template_params.to_h.deep_stringify_keys)
    valores = valores_do_publico(contato)
    return if params.nil? || valores.nil?

    params = params.merge('processed_params' => CampaignJourney::TemplateVariableKeys.apply(params['processed_params'], valores)) if valores.any?
    params.merge('name' => @atributos['campaign_template_name'].presence || params['name']).slice(*CAMPOS).compact
  end

  # {} sem variáveis do público; nil quando falta valor (a pessoa nem teria recebido).
  def valores_do_publico(contato)
    link = CampaignAudienceLink.for_campaign(@campanha)
    return {} if link.nil?

    variaveis = CampaignJourney::VariableBindings.new(link.variable_bindings, link.variable_defaults,
                                                      column_types: CampaignImports::ColumnTypes.stored(link.campaign_import))
    return {} unless variaveis.any?

    valores, faltando = variaveis.resolve(contato, linha_do_publico(link, contato))
    faltando.empty? ? valores : nil
  end

  def linha_do_publico(link, contato)
    rows = link.campaign_import&.campaign_import_rows
    rows ? rows.status_imported.where(contact_id: contato.id).order(:row_number).pick(:extra_values).to_h : {}
  end

  def topo(processed, template, inbox)
    return processed unless Whatsapp::Templates::HeaderMedia.media_type(template)

    header = processed['header']
    return processed if header.is_a?(Hash) && header['media_url'].present?

    midia = Whatsapp::Templates::HeaderMedia.dispatch_media(header, inbox, template)
    midia && processed.merge('header' => header.to_h.except('media_blob').merge(midia))
  end

  def produtos(processed, template, inbox)
    return processed unless Whatsapp::Templates::ProductParams.kind(template)

    conferencia = Whatsapp::Templates::DispatchProducts.new(inbox: inbox, template: template, processed: processed).call
    return processed.merge('products' => processed['products'].to_h.merge('catalog_id' => conferencia.catalog_id)) if conferencia.ok?

    @motivo = 'produto_indisponivel'
    nil
  end
end
