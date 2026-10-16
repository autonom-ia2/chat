# A marca de "o motor de entrega cuida desta conversa" (#1454). Fica nos atributos adicionais da conversa, gravada sob a
# trava dela, enquanto o motor (Crm::Entrega) segura a conversa até alguém ficar online ou espera o convidado pegar.
#
# Com a marca:
#   - o rodízio nativo (V1 e V2, OSS e Enterprise) pula a conversa: nunca duas atribuições, nem uma por cima da regra;
#   - o HandoffDrainJob tenta de novo a cada 2 minutos (segurando) ou limpa o convite vencido.
# A marca sai quando uma pessoa é atribuída, quando a conversa é resolvida ou quando alguém a entrega de novo a um robô
# (ConversationBotHandoff#end_bot_handoff_wait). Adiada, a conversa guarda a marca e volta à fila quando reabre.
module Crm::Entrega::Marca
  CHAVE = 'crm_entrega'.freeze
  SEGURANDO = 'segurando'.freeze
  CONVITE = 'convite'.freeze
  # Conversas que o rodízio nativo pode pegar.
  AUSENTE_SQL = "(conversations.additional_attributes ->> '#{CHAVE}') IS NULL".freeze
  PRESENTE_SQL = "(conversations.additional_attributes ->> '#{CHAVE}') IS NOT NULL".freeze

  module_function

  def presente?(conversation)
    dados(conversation).present?
  end

  def dados(conversation)
    atributos = conversation.additional_attributes
    valor = atributos.is_a?(Hash) ? atributos[CHAVE] : nil
    valor.is_a?(Hash) ? valor : nil
  end

  # Só na memória: quem chama grava (sob a trava). `motivo`: por que a conversa precisa de alguém (a origem);
  # `falha`: por que ainda não foi entregue. `desde` e `avisado_em` sobrevivem às novas tentativas, para medir a espera
  # e avisar uma vez só; `tentado_em` é da fila (HandoffDrainJob).
  # `detalhes`: `sugestao` (o nome que a IA sugeriu, para a próxima tentativa), `dono` (a pessoa a quem a entrega é
  # dirigida, R13 do #1150: a próxima tentativa segue esperando por ela) e `ate` (o fim do convite).
  def marcar(conversation, modo:, motivo:, falha: nil, **detalhes)
    anterior = dados(conversation) || {}
    valor = {
      'modo' => modo,
      'motivo' => motivo.to_s,
      'falha' => falha.presence,
      'desde' => desde_para(anterior, modo),
      'avisado_em' => anterior['avisado_em'].presence,
      'tentado_em' => anterior['tentado_em'].presence,
      'sugestao' => detalhes[:sugestao].presence,
      'dono_id' => detalhes[:dono]&.id,
      'ate' => detalhes[:ate]&.iso8601
    }.compact
    conversation.additional_attributes = (conversation.additional_attributes || {}).merge(CHAVE => valor)
  end

  # O prazo do convite conta do CONVITE: virar convite recomeça a contagem; o resto (inclusive convite → segurando)
  # mantém o começo da espera.
  def desde_para(anterior, modo)
    return Time.current.iso8601 if modo == CONVITE && anterior['modo'] != CONVITE

    anterior['desde'].presence || Time.current.iso8601
  end

  def tirar(conversation)
    return unless conversation.additional_attributes.is_a?(Hash)

    conversation.additional_attributes = conversation.additional_attributes.except(CHAVE)
  end

  # Há quanto tempo o motor segura ou convida esta conversa.
  def desde(conversation)
    Time.zone.parse(dados(conversation)&.dig('desde').to_s)
  rescue ArgumentError
    nil
  end

  # Marca o aviso de "não conseguimos chamar ninguém" (na memória), para ele sair uma vez só.
  def avisado!(conversation)
    valor = (dados(conversation) || {}).merge('avisado_em' => Time.current.iso8601)
    conversation.additional_attributes = conversation.additional_attributes.merge(CHAVE => valor)
  end

  # Um convite esperando a convidada pegar, ainda no prazo.
  def convite_aberto?(conversation)
    dados(conversation)&.dig('modo') == CONVITE && !convite_vencido?(conversation)
  end

  def convite_vencido?(conversation, agora: Time.current)
    valor = dados(conversation)
    return false unless valor && valor['modo'] == CONVITE

    ate = Time.zone.parse(valor['ate'].to_s)
    ate.nil? || ate <= agora
  rescue ArgumentError
    true
  end
end
