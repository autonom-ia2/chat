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

  # Só na memória: quem chama grava (sob a trava). `desde` sobrevive às novas tentativas, para medir a espera.
  def marcar(conversation, modo:, motivo:, sugestao: nil, ate: nil)
    anterior = dados(conversation) || {}
    valor = {
      'modo' => modo,
      'motivo' => motivo.to_s,
      'desde' => anterior['desde'].presence || Time.current.iso8601,
      'sugestao' => sugestao.presence,
      'ate' => ate&.iso8601
    }.compact
    conversation.additional_attributes = (conversation.additional_attributes || {}).merge(CHAVE => valor)
  end

  def tirar(conversation)
    return unless conversation.additional_attributes.is_a?(Hash)

    conversation.additional_attributes = conversation.additional_attributes.except(CHAVE)
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
