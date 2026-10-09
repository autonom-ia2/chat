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
  PASSAGEM = 'autonomia_nota_passagem'.freeze
  EPISODIO = 'autonomia_handoff_episode'.freeze
  TITULO = 'Antes de encaminhar, a IA não conseguiu:'.freeze

  def self.postar(conversation, passagem: nil, complemento: nil, marcas: nil)
    return if conversation.blank?

    motivos = ::Autonomia::Agents::Tools::RecusasRecentes.retirar(conversation.id)
    return if sem_conteudo?(motivos, passagem, complemento)

    nota = postar_com_lock(conversation.class.find(conversation.id), motivos, passagem, complemento, marcas)
    return unless nota

    Rails.logger.info("[autonomia][operate] nota do encaminhamento conv=#{conversation.id}")
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

  def self.texto_completo(motivos, conversation, passagem, complemento)
    [texto_da_passagem(conversation, passagem), complemento, (texto(motivos) if motivos.present?)].compact_blank.join("\n")
  end

  def self.texto_da_passagem(conversation, passagem)
    agent = passagem[:agent] || passagem['agent'] if passagem.respond_to?(:[])
    return if passagem.blank? || agent.blank?

    artigo = agent.voice == 'masculina' ? 'O' : 'A'
    motivo = ::Autonomia::Agents::Operate::EventLogger.curate_code(passagem[:reason] || passagem['reason'])
    motivo = I18n.t("autonomia.agents.handoff_reasons.#{motivo}", locale: conversation.account.locale, default: motivo)
    "#{artigo} #{agent.name} passou esta conversa para a equipe: #{motivo}."
  end

  def self.texto_com_passagem(conteudo, conversation, passagem)
    passagem_texto = texto_da_passagem(conversation, passagem)
    return conteudo if passagem_texto.blank? || conteudo.to_s.start_with?(passagem_texto)

    [passagem_texto, conteudo].compact_blank.join("\n")
  end

  def self.episodio_da(conversation)
    conversation.last_incoming_message&.id.to_s.presence || conversation.id.to_s
  end

  def self.sem_conteudo?(motivos, passagem, complemento)
    motivos.empty? && passagem.blank? && complemento.blank?
  end

  def self.postar_com_lock(conversation, motivos, passagem, complemento, marcas)
    conversation.with_lock do
      episodio = episodio_da(conversation)
      existing = nota_do_episodio(conversation, episodio)
      atualizar_passagem!(existing, conversation, passagem, marcas) if existing && passagem.present?

      existing || criar(
        conversation,
        texto_completo(motivos, conversation, passagem, complemento),
        episodio: episodio,
        passagem: passagem.present?,
        marcas: marcas
      )
    end
  end

  def self.atualizar_passagem!(existing, conversation, passagem, marcas)
    attributes = existing.content_attributes.to_h.merge(
      PASSAGEM => true,
      EPISODIO => episodio_da(conversation)
    )
    existing.update!(
      content: texto_com_passagem(existing.content, conversation, passagem),
      content_attributes: attributes.merge(marcas.to_h)
    )
  end

  def self.nota_do_episodio(conversation, episodio)
    conversation.messages.where(private: true).reverse_each.find do |message|
      attributes = message.content_attributes.to_h
      attributes[CHAVE].to_s == 'true' && attributes[EPISODIO].to_s == episodio.to_s
    end
  end

  def self.criar(conversation, texto, episodio:, passagem: false, marcas: nil)
    agent_inbox = ::Autonomia::Agents::AgentInbox.kept.find_by(inbox_id: conversation.inbox_id, account_id: conversation.account_id)
    attributes = { CHAVE => true, EPISODIO => episodio }
    attributes[PASSAGEM] = true if passagem
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: texto, message_type: 'outgoing', private: true,
        sender_type: 'AgentBot', sender_id: agent_inbox&.agent_bot_id,
        content_attributes: attributes.merge(marcas.to_h)
      )
    ).perform
  end

  private_class_method :texto, :linhas_dos_ramos, :linhas_das_falhas, :texto_completo, :texto_da_passagem,
                       :texto_com_passagem, :episodio_da, :sem_conteudo?, :postar_com_lock, :atualizar_passagem!,
                       :nota_do_episodio, :criar
end
