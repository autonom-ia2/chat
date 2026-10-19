# A conversa da enquete (ou do convite) ficou para trás (chat#1709, rodada de correção): está resolvida e o mesmo
# contato tem, na mesma caixa, uma conversa mais nova que não está resolvida. Um voto (ou uma resposta) nela fica só
# agregado na enquete e vira atividade escondida: não reabre a antiga (que tiraria o atendimento da conversa de agora)
# e não vira turno da IA. Comum à caixa WAHA comum e ao plano B do Híbrido (Waha::RichNative::PollVote e
# Waha::RichNative::EventResponses).
module Waha::RichNative::SupersededConversation
  module_function

  def superseded?(conversation)
    return false unless conversation&.resolved?

    Conversation.where(account_id: conversation.account_id, inbox_id: conversation.inbox_id, contact_id: conversation.contact_id)
                .where('id > ?', conversation.id).where.not(status: :resolved).exists?
  end
end
