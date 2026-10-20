# A conversa "Integração WhatsApp" (#1941, item 5): o canal interno do conector do WAHA comum. Cada caixa tem uma, com o
# contato de identifier `whatsapp.integration`, onde o conector deixa erros de tarefa interna ("message.cleanup") e os
# avisos de QR e de vínculo como se fossem mensagens de cliente. Decisão do Rodrigo (20/10): fora da lista de
# atendimento e das contagens. Abrir pelo endereço direto continua funcionando; o estado da conexão aparece na faixa da
# lista da caixa (GET waha_inboxes/:inbox_id/status).
# Um critério só, usado pela lista (Waha::ConversationFinderSemIntegracao), pelos filtros
# (Waha::FilterServiceSemIntegracao), pelas não lidas (Waha::NaoLidasSemIntegracao) e pela tela inicial
# (TelaInicial::Resumo). A busca global continua achando a conversa: procurar por ela é ir atrás dela, como abrir o link.
module Waha::IntegracaoDoConector
  IDENTIFIER = 'whatsapp.integration'.freeze

  def self.da_integracao?(conversation)
    conversation&.contact&.identifier == IDENTIFIER
  end

  def self.included(base)
    base.scope :fora_da_integracao_whatsapp, lambda {
      where.not(contact_id: Contact.where(identifier: IDENTIFIER).select(:id))
    }
  end
end
