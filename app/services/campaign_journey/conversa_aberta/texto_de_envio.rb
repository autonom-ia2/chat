# A mensagem escrita da conversa aberta (#1335) no formato que Whatsapp::Providers::WhatsappCloudService#send_message
# lê: texto puro, sem anexo e sem resposta a outra mensagem. Não é gravada pelo provedor: o erro da Meta fica no
# `last_error` do provedor, e quem grava a mensagem na conversa é o CampaignJourney::SentMessageRecorder.
class CampaignJourney::ConversaAberta::TextoDeEnvio
  attr_accessor :external_error, :status
  attr_reader :outgoing_content

  def initialize(texto)
    @outgoing_content = texto
  end

  def attachments
    []
  end

  def content_type
    'text'
  end

  def content_attributes
    {}
  end

  # O provedor chama save! depois de marcar o erro: nada a gravar aqui.
  def save!
    true
  end
end
