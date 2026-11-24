# #3099: confere a versão 2 da mensagem de cada canal na criação da campanha (ou, no e-mail, logo antes de enviar) e
# devolve o que fica guardado em `segunda_versao` do link. Recusa com CampaignJourney::DuasVersoes::Invalida (o código
# vai para a tela):
# - segunda_versao_vazia / segunda_versao_igual: a mesma regra da tela (duasVersoes.js#motivoDaSegunda), comparação
#   exata depois de tirar os espaços das pontas;
# - WhatsApp Oficial (D3): só um modelo aprovado da mesma caixa que pede as mesmas informações da versão 1 (as mesmas
#   variáveis, o mesmo tipo de arquivo no topo, o mesmo catálogo e o mesmo formato de oferta), para a ligação das
#   informações da versão 1 servir às duas;
# - E-mail (D2): só o assunto muda;
# - SMS e WhatsApp API: o texto da versão 2 passa pelas mesmas conferências de campos da versão 1.
module CampaignJourney::DuasVersoes::Segunda
  Invalida = CampaignJourney::DuasVersoes::Invalida
  ASSUNTO_MAXIMO = 250

  module_function

  # `modelos`: os modelos da caixa; `primeiro`: o modelo da versão 1.
  def whatsapp_cloud(dados, modelos:, primeiro:)
    nome = dados.to_h['template_name'].to_s.strip
    idioma = dados.to_h['template_language'].to_s.strip
    raise Invalida, 'segunda_versao_vazia' if nome.empty?

    modelo = Array(modelos).find { |candidato| aprovado?(candidato, nome, idioma) }
    raise Invalida, 'segunda_versao_modelo_nao_aprovado' unless modelo
    raise Invalida, 'segunda_versao_igual' if aprovado?(primeiro.to_h, modelo['name'], modelo['language'].to_s)
    raise Invalida, 'segunda_versao_outras_informacoes' unless mesmas_informacoes?(modelo, primeiro)

    { 'template_name' => modelo['name'], 'template_language' => modelo['language'], 'message' => corpo(modelo) }
  end

  def email(dados, primeiro:)
    assunto = texto!(dados.to_h['subject'], primeiro)
    raise Invalida, 'segunda_versao_longa' if assunto.size > ASSUNTO_MAXIMO

    { 'subject' => assunto }
  end

  # `defaults`: os textos padrão da versão 1 (por campo); os da versão 2 (`variable_defaults`) somam por cima.
  def sms(dados, campaign_import:, defaults:, primeiro:)
    texto = texto!(dados.to_h['message_body'], primeiro)
    padroes = padroes_da_segunda(texto, dados, defaults)
    CampaignJourney::SmsMessage.new(texto, campaign_import: campaign_import, defaults: padroes).validate!
    { 'message_body' => texto, 'variable_defaults' => padroes }
  rescue CampaignJourney::SmsMessage::Error => e
    raise Invalida.new(e.message, e.details)
  end

  # `conferir`: a conferência de campos do criador da WhatsApp API (levanta ArgumentError com o código).
  def whatsapp_api(dados, defaults:, primeiro:, conferir:)
    texto = texto!(dados.to_h['message_body'], primeiro)
    conferir.call(texto)
    { 'message_body' => texto, 'variable_defaults' => padroes_da_segunda(texto, dados, defaults) }
  end

  def texto!(valor, primeiro)
    texto = valor.to_s.strip
    raise Invalida, 'segunda_versao_vazia' if texto.empty?
    raise Invalida, 'segunda_versao_igual' if texto == primeiro.to_s.strip

    texto
  end

  # Os padrões só dos campos que a versão 2 usa, com espaços normalizados (como a versão 1).
  def padroes_da_segunda(texto, dados, defaults)
    campos = WhatsappApiCampaigns::TemplateRenderer.variables_in(texto)
    defaults.to_h.merge(dados.to_h['variable_defaults'].to_h).transform_keys(&:to_s).slice(*campos)
            .transform_values { |valor| valor.to_s.squish }.compact_blank
  end

  def aprovado?(modelo, nome, idioma)
    modelo['name'] == nome && modelo['language'].to_s.casecmp?(idioma) && modelo['status'].to_s.casecmp?('approved')
  end

  def mesmas_informacoes?(modelo, primeiro)
    CampaignJourney::TemplateVariableKeys.keys(modelo).sort == CampaignJourney::TemplateVariableKeys.keys(primeiro).sort &&
      Whatsapp::Templates::HeaderMedia.media_type(modelo) == Whatsapp::Templates::HeaderMedia.media_type(primeiro) &&
      Whatsapp::Templates::ProductParams.kind(modelo) == Whatsapp::Templates::ProductParams.kind(primeiro) &&
      Whatsapp::Templates::SendableFormat.offer_format?(modelo) == Whatsapp::Templates::SendableFormat.offer_format?(primeiro)
  end

  def corpo(modelo)
    Array(modelo['components']).find { |component| component['type'] == 'BODY' }&.dig('text').to_s
  end
end
