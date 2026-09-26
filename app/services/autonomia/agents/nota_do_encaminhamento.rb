# A NOTA DA EQUIPE NO ENCAMINHAMENTO (conversa 7057, 24/09/2026): quando a Lia passa a conversa para uma pessoa, o que
# as ferramentas não conseguiram fazer nos últimos minutos vira uma mensagem PRIVADA, que o cliente não recebe e que
# nenhum modelo lê. É o par da nota de quem ficou sem proposta (`Tools::NotaInterna`), para o caso em que nem houve
# cotação: a busca que não respondeu, a conferência que recusou.
#
# O texto é o ramo que a pessoa pediu e a IA não cota, quando houve (conversa 7150), e a frase de `Recusa::MOTIVOS` de
# cada código, com a contagem. Uma vez por encaminhamento: a lista é
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

  # O ramo que a pessoa pediu e a IA não cota (conversa 7150): uma linha por ramo, sem contagem, antes das falhas.
  LINHA_DO_RAMO = '- cotar %<ramo>s: a pessoa pediu este seguro, que a corretora trabalha e a IA não cota nesta conta'.freeze

  def self.texto(motivos)
    ramos, falhas = motivos.partition { |motivo| motivo.start_with?(::Autonomia::Agents::Tools::RecusasRecentes::PREFIXO_DO_RAMO) }
    [TITULO, *linhas_dos_ramos(ramos), *linhas_das_falhas(falhas)].join("\n")
  end

  def self.linhas_dos_ramos(ramos)
    ramos.uniq.map do |valor|
      ramo = valor.delete_prefix(::Autonomia::Agents::Tools::RecusasRecentes::PREFIXO_DO_RAMO)
      format(LINHA_DO_RAMO, ramo: ramo.tr('_', ' '))
    end
  end

  def self.linhas_das_falhas(falhas)
    falhas.tally.map do |motivo, vezes|
      frase = ::Autonomia::Agents::Tools::Recusa::MOTIVOS.fetch(motivo, ::Autonomia::Agents::Tools::Recusa::SEM_DESCRICAO)
      vezes > 1 ? "- #{frase} (#{vezes} vezes)" : "- #{frase}"
    end
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

  private_class_method :texto, :linhas_dos_ramos, :linhas_das_falhas, :criar
end
