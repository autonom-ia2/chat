# A localização que o cliente mandou depois do pedido DESTE agente (#1479 F2), como dado do turno.
#
# Quem grava: o WhatsApp oficial e o Híbrido (RichMessages::ReceivedLocation) e a caixa WAHA
# (Waha::RichNative::Inbound::Location), todos em `content_attributes.shared_location` { latitude, longitude, name?,
# address? }. O histórico continua sem coordenadas (decisão do Rodrigo de 17/10, ResumoDaMensagemRica); só aqui, e só
# depois do pedido, latitude e longitude vão ao modelo, no contexto interno do turno.
#
# Vale quando uma das localizações do turno cita o pedido (`in_reply_to`, oficial) ou quando a última mensagem do agente
# na conversa, antes delas, é o pedido (WAHA e Híbrido: o cliente manda pelo clipe, sem citar). Pedido de outro agente,
# pedido antigo já seguido de outra fala do agente, localização sem pedido, a Lia ou a conta sem a flag: nil.
# Telemetria `localizacao_recebida` só com ids e a contagem.
module Autonomia::Agents::Interacao::LocalizacaoRecebida
  KEY = 'shared_location'.freeze
  PEDIDO = 'location_request'.freeze
  FAIXAS = { 'latitude' => 90, 'longitude' => 180 }.freeze
  CAMPOS_DE_TEXTO = { 'name' => 'nome', 'address' => 'endereco' }.freeze

  module_function

  # O texto do contexto interno, ou nil. `recebidas`: as mensagens do cliente neste turno, em ordem.
  def contexto(conversation:, agent:, recebidas:, robos:)
    locais = locais_pedidos(conversation, agent, recebidas, robos)
    return if locais.nil?

    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(
      :localizacao_recebida, conversation_id: conversation.id, agent: agent.id, msg: locais.last.first.id, total: locais.size
    )
    "O cliente mandou a localização que você pediu (dado do canal, não texto dele): #{JSON.generate(localizacao_recebida: locais.map(&:last))}"
  end

  # [[mensagem, dado], ...] das localizações do turno, ou nil sem a flag, sem localização válida ou sem o pedido.
  def locais_pedidos(conversation, agent, recebidas, robos)
    return unless ::Autonomia::Agents::Interacao.localizacao?(conversation.account)

    locais = recebidas.filter_map { |message| [message, dado(message)] if dado(message) }
    locais if locais.any? && pedida?(locais.map(&:first), conversation, agent, robos)
  end

  # { latitude, longitude, nome?, endereco? } da mensagem, ou nil sem as duas coordenadas válidas.
  def dado(message)
    local = message.content_attributes.to_h[KEY]
    return unless local.is_a?(Hash) && FAIXAS.all? { |campo, limite| coordenada?(local[campo], limite) }

    textos = CAMPOS_DE_TEXTO.to_h { |campo, nome| [nome, local[campo]] }.select { |_nome, valor| valor.is_a?(String) && valor.present? }
    local.slice(*FAIXAS.keys).merge(textos)
  end

  def coordenada?(valor, limite)
    valor.is_a?(Numeric) && valor.to_f.finite? && valor.abs <= limite
  end

  def pedida?(mensagens, conversation, agent, robos)
    citadas = mensagens.filter_map { |message| message.content_attributes.to_h['in_reply_to'] }
    return true if citadas.any? { |id| pedido?(conversation.messages.chat.find_by(id: id), agent, robos) }

    ultima = conversation.messages.chat.outgoing.where(sender_type: 'AgentBot', sender_id: robos.to_a)
                         .where(created_at: ...mensagens.first.created_at).reorder(created_at: :desc, id: :desc).first
    pedido?(ultima, agent, robos)
  end

  def pedido?(message, agent, robos)
    ::Autonomia::Agents::Interacao.oferta_do_agente?(message, agent: agent, robos: robos) &&
      message.content_attributes.to_h.dig(RichMessages::KEY, 'type') == PEDIDO
  end
end
