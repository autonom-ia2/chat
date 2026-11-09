# A localização que o cliente mandou depois do pedido DESTE agente (#1479 F2), como dado do turno.
#
# Quem grava: o WhatsApp oficial e o Híbrido (RichMessages::ReceivedLocation) e a caixa WAHA
# (Waha::RichNative::Inbound::Location), todos em `content_attributes.shared_location` { latitude, longitude, name?,
# address?, live? }. Ao turno vão SÓ as coordenadas (número validado na faixa) e `ao_vivo` quando é localização ao
# vivo (o ponto inicial): nome e endereço são texto que vem do aparelho do cliente e já chegam ao modelo como fala dele
# (ResumoDaMensagemRica), nunca no contexto interno. O histórico continua sem coordenadas (decisão do Rodrigo de 17/10).
#
# Vale quando uma das localizações do turno cita o pedido (`in_reply_to`, oficial) ou quando a última mensagem do agente
# na conversa, antes delas, é o pedido (WAHA e Híbrido: o cliente manda pelo clipe, sem citar). O pedido é a mensagem
# deste agente com `location_request` ou com a marca `PedidoDeLocalizacao::MARCA` (o formato não saiu). O mapa e o
# cartão de contato (#1479 F3, `CartoesDoTurno::TOKEN`) não são fala: saem depois da resposta do mesmo turno e não tiram
# o pedido do lugar de última fala. Na voz, o pedido é a interação que o job posta depois do áudio, e conta. Pedido de outro
# agente, pedido antigo já seguido de outra fala do agente, localização sem pedido, a Lia ou a conta sem a flag: nil.
# As consultas (robôs do agente, mensagem citada, última fala) só rodam com a flag e com localização válida no turno.
# Telemetria `localizacao_recebida` só com ids e a contagem.
module Autonomia::Agents::Interacao::LocalizacaoRecebida
  KEY = 'shared_location'.freeze
  PEDIDO = 'location_request'.freeze
  FAIXAS = { 'latitude' => 90, 'longitude' => 180 }.freeze
  # A mensagem de cartão leva a chave do token em `content_attributes` (coluna json, gravada como texto JSON). O COALESCE
  # mantém a fala com a coluna nula: no `NOT`, um LIKE nulo a tiraria da busca.
  CARTAO = "COALESCE(content_attributes::text, '') LIKE ?".freeze

  module_function

  # O texto do contexto interno, ou nil. `recebidas`: as mensagens do cliente neste turno, em ordem. `robos`: um
  # bloco que devolve os robôs-espelho do agente (`Interacao.robos`), chamado só quando há o que conferir.
  def contexto(conversation:, agent:, recebidas:, robos:)
    locais = locais_pedidos(conversation, agent, recebidas, robos)
    return if locais.nil?

    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(
      :localizacao_recebida, conversation_id: conversation.id, agent: agent.id, msg: locais.last.first.id, total: locais.size
    )
    "O cliente mandou a localização que você pediu (coordenadas do canal): #{JSON.generate(localizacao_recebida: locais.map(&:last))}"
  end

  # [[mensagem, dado], ...] das localizações do turno, ou nil sem a flag, sem localização válida ou sem o pedido.
  def locais_pedidos(conversation, agent, recebidas, robos)
    return unless aplica?(conversation, agent)

    locais = recebidas.filter_map do |message|
      dado = dado(message)
      [message, dado] if dado
    end
    locais if locais.any? && pedida?(locais.map(&:first), conversation, agent, robos.call)
  end

  # Fora da Lia e com a flag da conta.
  def aplica?(conversation, agent)
    agent.agent_type != 'insurance_quote' && ::Autonomia::Agents::Interacao.localizacao?(conversation.account)
  end

  # { latitude, longitude, ao_vivo? } da mensagem, ou nil sem as duas coordenadas válidas.
  def dado(message)
    local = message.content_attributes.to_h[KEY]
    return unless local.is_a?(Hash) && FAIXAS.all? { |campo, limite| coordenada?(local[campo], limite) }

    local.slice(*FAIXAS.keys).merge(local['live'] == true ? { 'ao_vivo' => true } : {})
  end

  def coordenada?(valor, limite)
    valor.is_a?(Numeric) && valor.to_f.finite? && valor.abs <= limite
  end

  def cartao
    ActiveRecord::Base.sanitize_sql_like(::Autonomia::Agents::Operate::CartoesDoTurno::TOKEN)
  end

  def pedida?(mensagens, conversation, agent, robos)
    citadas = mensagens.filter_map { |message| message.content_attributes.to_h['in_reply_to'] }
    return true if citadas.any? && conversation.messages.chat.where(id: citadas).any? { |citada| pedido?(citada, agent, robos) }

    ultima = conversation.messages.chat.outgoing.where(sender_type: 'AgentBot', sender_id: robos.to_a)
                         .where(created_at: ...mensagens.first.created_at).where.not(CARTAO, "%#{cartao}%")
                         .reorder(created_at: :desc, id: :desc).first
    pedido?(ultima, agent, robos)
  end

  # A mensagem é o pedido de localização DESTE agente: do robô-espelho de um vínculo dele, com a marca dele, e com o
  # formato do pedido ou a marca do pedido.
  def pedido?(message, agent, robos)
    do_agente?(message, agent, robos) && formato_de_pedido?(message.content_attributes.to_h)
  end

  def do_agente?(message, agent, robos)
    return false unless message&.outgoing? && message.sender_type == 'AgentBot' && robos.include?(message.sender_id)

    message.content_attributes.to_h['autonomia_agent_id'] == agent.id
  end

  def formato_de_pedido?(atributos)
    formato = atributos[RichMessages::KEY]
    atributos[::Autonomia::Agents::Interacao::PedidoDeLocalizacao::MARCA] == true || (formato.is_a?(Hash) && formato['type'] == PEDIDO)
  end
end
