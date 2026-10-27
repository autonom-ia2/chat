# #2211 — conversas no mesmo formato da lista (o card novo usa o payload de sempre); mensagens com quem mandou, quando e
# o texto achado (o do áudio, quando foi a transcrição que achou); pessoas sem conversa no formato de contato.
json.payload do
  conversations = @result[:conversations]
  crm_funnels = Crm::Conversations::PipelineIds.for_current_user(conversations)
  # Como na lista (conversations/index): o "Devolver para" do card vem junto.
  veio_da_ia = Conversations::FicarAoEnviar.ligado?(Current.account) ? Crm::Passagens::VeioDaIa.da_lista(conversations) : nil
  json.conversations do
    json.array! conversations do |conversation|
      json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: conversation,
                                                                  crm_funnels: crm_funnels, veio_da_ia: veio_da_ia
    end
  end
  json.messages do
    json.array! @result[:messages] do |message|
      json.partial! 'api/v1/accounts/busca_da_lista/mensagem', formats: [:json], message: message
    end
  end
  json.contacts do
    json.array! @result[:contacts] do |contact|
      json.partial! 'api/v1/models/contact', formats: [:json], resource: contact
    end
  end
  json.telefone_novo @result[:telefone_novo]
  # E-mail que ninguém da conta tem, em minúsculas (nil quando não é e-mail, já existe ou falta poder criar contato).
  json.email_novo @result[:email_novo]
  # Seções que passaram do tempo e voltaram vazias.
  json.parcial @result[:parcial]
end
