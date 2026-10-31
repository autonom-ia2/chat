# O MAPA E O CARTÃO DE CONTATO DO TURNO (#1479 F3), na entrega do Responder: cada cartão que `enviar_localizacao` e
# `enviar_contato` marcaram (`Delivery#cartoes`) sai numa mensagem própria, DEPOIS do texto, nos três caminhos.
#
#   - clássico e áudio (`postar!`): dentro do mesmo lock da resposta, depois dela (e da interação, no áudio). O cartão
#     já enviado não sai de novo: cada mensagem leva um token próprio (`autonomia_cartao_token`, o turno + o tipo + a
#     chave), conferido antes de postar. Ela NÃO leva `autonomia_reply_to_message_id`: o `already_replied?` continua
#     olhando só o texto, então o cartão nunca faz o retry pular o texto, e o texto já enviado não pula o cartão (quem
#     chama posta os cartões também quando a guarda diz "já respondido").
#   - em pedaços (`pedacos`): cada cartão é um pedaço a mais NO FIM, depois do texto e da interação. A idempotência é a
#     do pedaço (`autonomia_chunk_token`). `text` é a versão em texto do cartão, que um worker antigo manda como está;
#     `corpo` é o conteúdo vazio que vai junto do formato (`ChunkedDeliveryJob#build_message!`).
#
# O conteúdo vai vazio (o formato da Meta não tem corpo). Na caixa que não leva o formato (e-mail, chat do site), a mesma
# regra da interação (`Interacao.sai_o_formato?`): sai a versão em texto, sem `rich_message`. Nada aqui é logado.
class Autonomia::Agents::Operate::CartoesDoTurno
  TOKEN = 'autonomia_cartao_token'.freeze

  def initialize(conversation:, agent_inbox:, agent:, delivery:)
    @conversation = conversation
    @agent_inbox = agent_inbox
    @agent = agent
    @delivery = delivery
  end

  def cartoes
    @cartoes ||= Array(@delivery&.cartoes)
  end

  def vazio?
    cartoes.empty?
  end

  # Clássico e áudio: posta, dentro do lock de quem chama, cada cartão que ainda não saiu neste turno. -> as mensagens.
  def postar!
    cartoes.filter_map { |cartao| postar_cartao!(cartao) unless postado?(token(cartao)) }
  end

  # Em pedaços: um pedaço por cartão, para ir depois de todos os da resposta.
  def pedacos
    cartoes.map do |cartao|
      em_texto = em_texto(cartao)
      formato = sai_o_formato?(cartao) ? { 'corpo' => '', 'rich_message' => cartao['rich_message'] } : {}
      { 'text' => em_texto, 'type' => 'text',
        'delay_ms' => ::Autonomia::Agents::Operate::ReplyChunker.delay_seguinte(em_texto) }.merge(formato)
    end
  end

  private

  def postar_cartao!(cartao)
    formato = sai_o_formato?(cartao)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: formato ? '' : em_texto(cartao), message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @agent_inbox.agent_bot_id, private: false,
        content_attributes: {
          'autonomia_agent_id' => @agent.id, TOKEN => token(cartao), **(formato ? { RichMessages::KEY => cartao['rich_message'] } : {})
        }
      )
    ).perform
  end

  def token(cartao)
    "#{@delivery.turno}:cartao:#{cartao['tipo']}:#{cartao['chave']}"
  end

  # Prefiltra por LIKE (token distintivo) e confirma no hash, como `ChunkedDeliveryJob#chunk_posted?`.
  def postado?(token)
    @conversation.messages.outgoing.where(sender_type: 'AgentBot')
                 .where('content_attributes::text LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(token)}%")
                 .any? { |message| message.content_attributes.to_h[TOKEN].to_s == token }
  end

  def sai_o_formato?(cartao)
    ::Autonomia::Agents::Interacao.sai_o_formato?(cartao['rich_message'], '', @conversation)
  end

  def em_texto(cartao)
    formato = cartao['rich_message']
    RichMessages.type_class(formato['type']).new(formato).fallback_text('')
  end
end
