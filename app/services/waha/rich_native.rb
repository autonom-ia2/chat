# Mensagem rica nativa pelo motor WAHA (chat#1709): o que é comum a quem envia pelo motor — o plano B do WhatsApp
# Híbrido (fase 1, WhatsappHybrid::RichNative) e a caixa WAHA comum (fase 2). Sem caixa nem transporte aqui.
#
# Flag por conta `whatsapp_rich_native` (config/features.yml). Desligada: tudo sai como texto, como antes.
#
# Chaves de `content_attributes` que esta frente usa:
# - `rich_message` (chat#1473): o formato pedido; não é alterado;
# - `rich_message_sent_as`: 'native' quando saiu no formato do motor ('text' continua sendo a marca do #1555);
# - `in_reply_to` (Chatwoot): na resposta do cliente, o id numérico da mensagem de opções respondida;
# - `selected_option` (chat#1473): `{ id, title }` da opção tocada, com o `id` ORIGINAL da opção (sem a referência).
#
# O `rowId` de cada linha da lista leva a opção e a mensagem: "<id da opção>|<id da mensagem no Chatwoot>"
# (REPLY_SEPARATOR). Na volta, `split_row_id` separa pelo ÚLTIMO separador; quem lê a resposta grava a opção sem a
# referência e liga a resposta à mensagem certa mesmo com listas antigas na conversa.
module Waha::RichNative
  FLAG = 'whatsapp_rich_native'.freeze
  SENT_AS = 'native'.freeze
  KINDS = Waha::RichPayload::KINDS
  REPLY_SEPARATOR = '|'.freeze

  module_function

  def enabled?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  def sent_native?(message)
    message.content_attributes.to_h[RichMessages::SENT_AS_KEY] == SENT_AS
  end

  # "<opção>|<mensagem>" quando cabe em `max`; senão, só a opção (a volta cai na busca pela última lista). Lista com id de
  # opção que tem o separador nunca sai nativa (Waha::RichPayload): todo `rowId` nativo com "|" é nosso, com a
  # referência numérica no fim.
  def row_id(option_id, message_id, max:)
    return option_id if message_id.blank?

    combined = [option_id, message_id].join(REPLY_SEPARATOR)
    combined.length <= max ? combined : option_id
  end

  # [id da opção, id da mensagem] a partir do `rowId` devolvido; [row_id, nil] quando não há referência numérica.
  def split_row_id(row_id)
    option_id, separator, reference = row_id.to_s.rpartition(REPLY_SEPARATOR)
    return [row_id.to_s, nil] if separator.empty? || option_id.empty? || !digits?(reference)

    [option_id, reference.to_i]
  end

  def digits?(text)
    text.present? && text.delete('0-9').empty?
  end

  # `source_id` provisório de quem vai ao motor sem id gerado antes (a lista): gravado ANTES do pedido, para um novo
  # SendReplyJob não reenviar (o Base::SendOnChannelService ignora mensagem com `source_id`) se algo quebrar depois
  # do pedido e antes de o id físico ser gravado. A resposta troca pelo id físico; sem id na resposta, fica o
  # provisório. Nem o ack (Redis pelo id físico) nem a ligação da resposta (id da mensagem no `rowId`) leem este valor.
  PENDING_PREFIX = 'waha-native-pending-'.freeze

  def pending_source_id(message)
    "#{PENDING_PREFIX}#{message.id}"
  end

  # Sem as validações do modelo (a de rajada recusaria numa conversa movimentada). Levanta: é antes do pedido, nada saiu.
  def write_source_id!(message, source_id)
    message.with_lock do
      message.source_id = source_id
      message.save!(validate: false)
    end
  end

  # Grava, depois que o motor aceitou, a marca do formato e o id físico no source_id. Sem as validações do modelo: a
  # de rajada (`prevent_message_flooding`) recusaria a gravação numa conversa movimentada, e a mensagem já saiu.
  # Devolve true quando gravou. Erro aqui não derruba o envio (viraria falha e reenvio): vai para o log e o tracker.
  def mark_sent!(message, physical_id)
    message.with_lock do
      message.source_id = physical_id if physical_id.present?
      message.content_attributes = message.content_attributes.to_h.merge(RichMessages::SENT_AS_KEY => SENT_AS)
      message.save!(validate: false)
    end
    true
  rescue StandardError => e
    Rails.logger.error("[waha] rich native mark failed message=#{message.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: message.account).capture_exception
    false
  end

  # Mensagem nossa de opções que saiu nativa. O conteúdo é JSON gravado como texto: o filtro é em Ruby, sobre poucas
  # linhas.
  def native_options?(message)
    rich = message.content_attributes.to_h[RichMessages::KEY]
    rich.is_a?(Hash) && rich['type'] == 'options' && sent_native?(message)
  end

  # Os ids das opções oferecidas (soltas ou em seções), em texto.
  def option_ids(message)
    rich = message.content_attributes.to_h[RichMessages::KEY]
    options = rich['sections'].is_a?(Array) ? rich['sections'].flat_map { |section| Array(section.try(:[], 'options')) } : Array(rich['options'])
    options.filter_map { |option| option['id'].to_s if option.is_a?(Hash) && option['id'].present? }
  end

  # Quem pode mandar nativo (um por transporte): o plano B do Híbrido (fase 1) e a caixa WAHA comum (fase 2). Cada um
  # responde `native_types_for(conversation, api_reply:)` com os tipos que manda, fazendo primeiro as checagens sem
  # consulta.
  def routes
    [WhatsappHybrid::RichNative, Waha::RichNative::WahaInbox]
  end

  # Os tipos que saem nativos nesta conversa agora (campo `whatsapp_api_rich_native` da conversa, para a tela do "+").
  # `api_reply`: o `whatsapp_api_reply?` já calculado por quem chama (o jbuilder e o evento ao vivo), para não
  # perguntar ao roteador duas vezes.
  def types_for(conversation, api_reply: nil)
    KINDS & routes.flat_map { |route| route.native_types_for(conversation, api_reply: api_reply) }
  end

  # A conta para ler a flag sem consulta por conversa: a já carregada na conversa, ou a do request (`Current.account`,
  # que as rotas da conta preenchem) quando é a mesma. Fora de um request (evento de uma conversa só), carrega. Num job,
  # `Current.account` pode ter sobrado na thread: a conferência por id evita ler a flag da conta errada.
  def account_of(conversation)
    return conversation.account if conversation.association(:account).loaded?
    return Current.account if Current.account&.id == conversation.account_id

    conversation.account
  end
end
