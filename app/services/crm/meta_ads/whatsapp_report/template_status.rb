# Os dois modelos que o número Oficial precisa para mandar o resumo e o alerta (#1100, F4b).
#
# O fork não cria nem submete modelo à Meta: a pessoa cria no Gerenciador do WhatsApp com o texto exato (i18n de
# servidor, `meta_ads_whatsapp_report.templates`) e aqui só se lê o que a caixa já sincronizou em
# `message_templates`. Vale o nome exato, o idioma pt_BR e o status da Meta.
module Crm::MetaAds::WhatsappReport::TemplateStatus
  NAMES = { 'summary' => 'chat2you_resumo_anuncios', 'alert' => 'chat2you_alerta_anuncio' }.freeze
  LANGUAGE = 'pt_BR'.freeze
  APPROVED = 'APPROVED'.freeze
  REJECTED = 'REJECTED'.freeze

  module_function

  # { 'summary' => 'approved|pending|rejected|missing', 'alert' => ... }
  def for(channel)
    NAMES.keys.index_with { |kind| status(channel, kind) }
  end

  # 'missing' sem o modelo; 'approved' e 'rejected' como a Meta diz; qualquer outro status (em análise,
  # pausado, em recurso) é 'pending': ainda não dá para enviar.
  def status(channel, kind)
    template = find(channel, kind)
    return 'missing' if template.nil?

    case template['status'].to_s.upcase
    when APPROVED then 'approved'
    when REJECTED then 'rejected'
    else 'pending'
    end
  end

  def approved(channel, kind)
    template = find(channel, kind)
    template if template && template['status'].to_s.upcase == APPROVED
  end

  def find(channel, kind)
    name = NAMES.fetch(kind)
    Array(channel.message_templates).find { |template| template['name'] == name && template['language'] == LANGUAGE }
  end
end
