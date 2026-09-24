# A NOTA DA EQUIPE NO ENCAMINHAMENTO (conversa 7057, 24/09/2026): quando a Lia passa a conversa para uma pessoa, o que
# as ferramentas não conseguiram fazer nos últimos minutos vira uma mensagem PRIVADA, que o cliente não recebe e que
# nenhum modelo lê. É o par da nota de quem ficou sem proposta (`Tools::NotaInterna`), para o caso em que nem houve
# cotação: a busca que não respondeu, a conferência que recusou.
#
# O texto é só a frase de `Recusa::MOTIVOS` de cada código, com a contagem. Uma vez por encaminhamento: a lista é
# apagada ao ser lida. Nunca levanta: não pode derrubar o encaminhamento.
class Autonomia::Agents::NotaDoEncaminhamento
  CHAVE = 'autonomia_nota_do_encaminhamento'.freeze
  TITULO = 'Antes de encaminhar, a IA não conseguiu:'.freeze

  def self.postar(conversation)
    return if conversation.blank?

    motivos = ::Autonomia::Agents::Tools::RecusasRecentes.retirar(conversation.id)
    return if motivos.empty?

    nota = criar(conversation, texto(motivos))
    Rails.logger.info("[autonomia][operate] nota do encaminhamento conv=#{conversation.id}") if nota
    nota
  rescue StandardError => e
    Rails.logger.warn("[autonomia][operate] nota_do_encaminhamento_falhou conv=#{conversation&.id} #{e.class}")
    nil
  end

  def self.texto(motivos)
    linhas = motivos.tally.map do |motivo, vezes|
      frase = ::Autonomia::Agents::Tools::Recusa::MOTIVOS.fetch(motivo, ::Autonomia::Agents::Tools::Recusa::SEM_DESCRICAO)
      vezes > 1 ? "- #{frase} (#{vezes} vezes)" : "- #{frase}"
    end
    [TITULO, *linhas].join("\n")
  end

  def self.criar(conversation, texto)
    agent_inbox = ::Autonomia::Agents::AgentInbox.find_by(inbox_id: conversation.inbox_id, account_id: conversation.account_id)
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: texto, message_type: 'outgoing', private: true,
        sender_type: 'AgentBot', sender_id: agent_inbox&.agent_bot_id,
        content_attributes: { CHAVE => true }
      )
    ).perform
  end

  private_class_method :texto, :criar
end
