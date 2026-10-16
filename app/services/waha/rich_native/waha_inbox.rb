# Caixa WAHA comum (Channel::Api com provider 'waha') na mensagem rica nativa (chat#1709, fase 2).
# Quem envia é o conector do WAHA (customizado): o chat2you não chama o motor nessa caixa, só decide, prepara o pedido
# (`waha_native` no webhook da caixa) e lê a volta (`waha_list_reply`).
#
# Uma mensagem sai nativa só se TODAS valerem (a mesma regra para a decisão na criação, `delivery_mode` e `types_for`):
# - flag `whatsapp_rich_native` na conta;
# - caixa WAHA comum cujo `webhook_url` começa pela URL de um motor listado (Waha::EngineCapabilities.engine_for);
# - o motor declara o tipo em `/api/server/version` (Waha::EngineCapabilities.types);
# - o tradutor monta o pedido (Waha::RichPayload.build, com o `content` cru).
module Waha::RichNative::WahaInbox
  module_function

  # Os tipos que esta caixa manda nativo agora. Sem consulta ao banco quando a caixa e o canal já vêm carregados (a
  # lista de conversas carrega `inbox: :channel`); motor sem lista no ENV sai antes de tudo.
  def types_for_inbox(inbox, account)
    return [] unless inbox&.channel_type == 'Channel::Api' && Waha::EngineCapabilities.engines.any?

    channel = inbox.channel
    return [] unless channel.waha_provider?

    engine = Waha::EngineCapabilities.engine_for(channel.webhook_url)
    return [] if engine.nil? || !Waha::RichNative.enabled?(account)

    Waha::EngineCapabilities.types(engine)
  end

  # As ações sobre mensagem já enviada (chat#1709, fase 3: 'react', 'edit') que o motor desta caixa declara, com a flag.
  # As mesmas checagens baratas de `types_for_inbox`, na mesma ordem. 'edit' só com o renderer do WhatsApp do chat#1740
  # (o conector exige o texto já formatado, Waha::RichNative::OutgoingHints.renderer_ready?).
  def actions_for_inbox(inbox, account)
    return [] unless inbox&.channel_type == 'Channel::Api' && Waha::EngineCapabilities.engines.any?

    channel = inbox.channel
    return [] unless channel.waha_provider?

    engine = Waha::EngineCapabilities.engine_for(channel.webhook_url)
    return [] if engine.nil? || !Waha::RichNative.enabled?(account)

    with_renderer(Waha::EngineCapabilities.actions(engine))
  end

  # `edit` precisa do texto já formatado pelo renderer do chat#1740.
  def with_renderer(actions)
    Waha::RichNative::OutgoingHints.renderer_ready? ? actions : actions - ['edit']
  end

  # Campo `whatsapp_api_message_actions` da conversa (o painel mostra "Reagir" e "Editar" só com ele).
  def message_actions_for(conversation)
    return [] unless conversation.inbox&.channel_type == 'Channel::Api' && Waha::EngineCapabilities.engines.any?

    actions_for_inbox(conversation.inbox, Waha::RichNative.account_of(conversation))
  end

  # Rota de `Waha::RichNative.types_for` (o campo `whatsapp_api_rich_native` da conversa). Caixa WAHA não tem janela.
  def native_types_for(conversation, api_reply: nil) # rubocop:disable Lint/UnusedMethodArgument
    return [] unless conversation.inbox&.channel_type == 'Channel::Api' && Waha::EngineCapabilities.engines.any?

    types_for_inbox(conversation.inbox, Waha::RichNative.account_of(conversation))
  end

  # A decisão de uma mensagem: tipo que o motor declara (checagens baratas primeiro: caixa de outro tipo ou lista de
  # motores vazia saem sem consulta), só o que o webhook da caixa de fato entrega (as travas do
  # RichMessages::ApiInboxSentAsText), formato sem erro e pedido que o tradutor monta.
  def native_for?(message)
    return false unless RichMessages.rich?(message) && RichMessages.type_class_of(message)
    return false unless types_for_inbox(message.inbox, message.account).include?(message.content_attributes[RichMessages::KEY]['type'])
    return false unless RichMessages.goes_to_channel?(message) && RichMessages::ApiInboxSentAsText.delivered_by_inbox_webhook?(message)

    RichMessages.error_for(message).nil? && payload_for(message).present?
  end

  # O pedido ao motor. `reference`: o id da mensagem, que vai em cada `rowId` da lista (na criação ainda não existe).
  def payload_for(message, reference: nil)
    rich = message.content_attributes[RichMessages::KEY]
    Waha::RichPayload.build(rich, body: message.content.to_s, locale: message.account.locale, reference: reference)
  end
end
