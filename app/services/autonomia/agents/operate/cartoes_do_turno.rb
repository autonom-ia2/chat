# O MAPA E O CARTÃO DE CONTATO DO TURNO (#1479 F3): cada cartão que `enviar_localizacao` e `enviar_contato` marcaram
# (`Delivery#cartoes`) sai numa mensagem própria, DEPOIS da mensagem âncora do turno e só quando ela saiu para o canal.
#
# A ÂNCORA GRAVA OS CARTÕES (`autonomia_cartoes`: tipo, chave, rich_message e token), na hora em que é postada:
#   - clássico: a mensagem de texto (`Responder#post_reply!`);
#   - voz: a última mensagem postada do turno (o áudio, ou a interação quando ela existe);
#   - em pedaços: o ÚLTIMO pedaço, pela `marca` dele (`ChunkedDeliveryJob#build_message!`). Os cartões não viram pedaço.
# Quem posta é o `EnviarCartoesJob`, enfileirado depois do lock e do commit (pelo Responder; nos pedaços, pelo
# ChunkedDeliveryJob logo depois do pedaço que os leva). O retry do turno que acha a resposta já postada usa os cartões
# GRAVADOS na âncora (`ancora_do_turno`), nunca os do novo run: o retry nunca manda um cartão diferente do primeiro.
#
# O cartão já postado não sai de novo: cada mensagem leva o token dele (`autonomia_cartao_token`: o turno + o tipo + a
# chave), conferido sob o lock da conversa antes de postar. Ela NÃO leva `autonomia_reply_to_message_id`: o
# `already_replied?` continua olhando só a resposta. O conteúdo vai vazio (o formato da Meta não tem corpo); na caixa
# que não leva o formato (e-mail, chat do site), a mesma regra da interação (`Interacao.sai_o_formato?`): sai a versão
# em texto, sem `rich_message`. Nada aqui é logado.
class Autonomia::Agents::Operate::CartoesDoTurno
  TOKEN = 'autonomia_cartao_token'.freeze
  NA_ANCORA = 'autonomia_cartoes'.freeze
  CAMPOS = %w[tipo chave rich_message].freeze

  class << self
    # Os cartões marcados no turno, com o token, para gravar na âncora. {} sem cartão: a âncora fica como sempre.
    def marca(delivery)
      cartoes = Array(delivery&.cartoes)
      return {} if cartoes.empty?

      { NA_ANCORA => cartoes.map { |cartao| cartao.slice(*CAMPOS).merge('token' => token(delivery.turno, cartao)) } }
    end

    def token(turno, cartao)
      "#{turno}:cartao:#{cartao['tipo']}:#{cartao['chave']}"
    end

    def da_ancora(message)
      Array(message&.content_attributes.to_h[NA_ANCORA]).select { |cartao| cartao.is_a?(Hash) && cartao['token'].present? }
    end

    # A âncora já postada deste turno (a resposta do robô à mensagem do cliente que leva os cartões), ou nil. Prefiltra
    # por LIKE (chave distintiva) e confirma no hash, como `ChunkedDeliveryJob#chunk_posted?`.
    def ancora_do_turno(conversation, reply_to_message_id)
      return if reply_to_message_id.blank?

      conversation.messages.outgoing.where(sender_type: 'AgentBot')
                  .where('content_attributes::text LIKE ?', "%#{NA_ANCORA}%").reorder(:id)
                  .select { |message| message.content_attributes.to_h['autonomia_reply_to_message_id'].to_s == reply_to_message_id.to_s }
                  .reverse.find { |message| da_ancora(message).any? }
    end
  end

  def initialize(ancora)
    @ancora = ancora
    @conversation = ancora.conversation
  end

  def cartoes
    @cartoes ||= self.class.da_ancora(@ancora)
  end

  # A mensagem que o cartão espera sair: a do cartão anterior da lista (já postado, a ordem é a da lista) ou a âncora.
  def anterior_de(cartao)
    indice = cartoes.index(cartao)
    return @ancora if indice.nil? || indice.zero?

    postada(cartoes[indice - 1]['token']) || @ancora
  end

  def postado?(cartao)
    postada(cartao['token']).present?
  end

  # Posta o cartão sob o lock da conversa, conferindo de novo que ele não saiu (dois jobs da mesma âncora). -> a
  # mensagem, ou nil quando outro job já o postou. Erro sobe para quem chama.
  def postar!(cartao)
    @conversation.with_lock do
      postado?(cartao) ? nil : construir!(cartao)
    end
  end

  private

  def construir!(cartao)
    formato = sai_o_formato?(cartao)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: formato ? '' : em_texto(cartao), message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: @ancora.sender_id, private: false,
        content_attributes: {
          'autonomia_agent_id' => @ancora.content_attributes.to_h['autonomia_agent_id'], TOKEN => cartao['token'],
          **(formato ? { RichMessages::KEY => cartao['rich_message'] } : {})
        }
      )
    ).perform
  end

  def postada(token)
    @conversation.messages.outgoing.where(sender_type: 'AgentBot')
                 .where('content_attributes::text LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(token)}%")
                 .find { |message| message.content_attributes.to_h[TOKEN].to_s == token }
  end

  def sai_o_formato?(cartao)
    ::Autonomia::Agents::Interacao.sai_o_formato?(cartao['rich_message'], '', @conversation)
  end

  def em_texto(cartao)
    formato = cartao['rich_message']
    RichMessages.type_class(formato['type']).new(formato).fallback_text('')
  end
end
