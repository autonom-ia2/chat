# O MAPA E O CARTÃO DE CONTATO DO TURNO (#1479 F3): cada cartão que `enviar_localizacao` e `enviar_contato` marcaram
# (`Delivery#cartoes`) sai numa mensagem própria, DEPOIS da mensagem âncora do turno e só quando ela saiu para o canal.
#
# A ÂNCORA GRAVA OS CARTÕES (`autonomia_cartoes`: tipo, chave, rich_message e token), na hora em que é postada:
#   - clássico: a mensagem de texto (`Responder#post_reply!`);
#   - voz: o áudio (a ordem da interação, que sai sem anexo e pode passar à frente dele, fica para o PR próprio);
#   - em pedaços: o ÚLTIMO pedaço. Os cartões não viram pedaço. Na `marca` dele vão SÓ as referências (tipo, chave,
#     token, `referencias`): os argumentos do job vão ao log INFO, e endereço, coordenada e telefone não. O
#     `ChunkedDeliveryJob#build_message!` resolve cada cartão pela página na hora de postar (`resolver`); o que não
#     resolve mais (a página mudou) fica fora, com `cartao_descartado` motivo=pagina_mudou. A mensagem no banco grava o
#     cartão completo: o banco não é log.
# Quem posta é o `EnviarCartoesJob`, enfileirado depois do lock e do commit (pelo Responder; nos pedaços, pelo
# ChunkedDeliveryJob logo depois do pedaço que os leva). O retry do turno que acha a resposta já postada usa os cartões
# GRAVADOS na âncora (`ancora_do_turno`), nunca os do novo run: o retry nunca manda um cartão diferente do primeiro.
#
# O cartão já postado não sai de novo: cada mensagem leva o token dele (`autonomia_cartao_token`: o turno + o tipo + a
# chave), conferido sob o lock da conversa antes de postar. Sob o mesmo lock, o cartão não sai por cima de uma pessoa da
# equipe que escreveu ao cliente depois da âncora (`PessoaDaEquipe.respondeu_depois?`), nem com a conta desligada
# (`CartaoDaPagina.ligado?`). Não é o `still_eligible?` inteiro: ele barraria o cartão do turno que pediu passagem. A
# desistência fica gravada na âncora (`autonomia_cartoes_encerrados`, `encerrar!`): um retry tardio não manda o cartão.
# A mensagem do cartão NÃO leva `autonomia_reply_to_message_id`: o `already_replied?` continua olhando só a resposta.
# O conteúdo vai vazio (o formato da Meta não tem corpo); na caixa que não leva o formato (e-mail, chat do site), a
# mesma regra da interação (`Interacao.sai_o_formato?`): sai a versão em texto, sem `rich_message`. O log leva só ids.
class Autonomia::Agents::Operate::CartoesDoTurno
  TOKEN = 'autonomia_cartao_token'.freeze
  NA_ANCORA = 'autonomia_cartoes'.freeze
  ENCERRADOS = 'autonomia_cartoes_encerrados'.freeze
  CAMPOS = %w[tipo chave rich_message].freeze
  REFERENCIA = %w[tipo chave token].freeze
  NATIVO = ::Autonomia::Agents::Tools::Native::CartaoDaPagina

  class << self
    # Os cartões marcados no turno, com o token, para gravar na âncora. {} sem cartão: a âncora fica como sempre.
    def marca(delivery)
      cartoes = Array(delivery&.cartoes)
      return {} if cartoes.empty?

      { NA_ANCORA => cartoes.map { |cartao| cartao.slice(*CAMPOS).merge('token' => token(delivery.turno, cartao)) } }
    end

    # A marca sem o dado do cartão, para os argumentos do job de pedaços. {} sem cartão.
    def referencias(marca)
      return {} if marca.blank?

      { NA_ANCORA => marca[NA_ANCORA].map { |cartao| cartao.slice(*REFERENCIA) } }
    end

    # A marca do último pedaço com as referências trocadas pelos cartões resolvidos pela página agora
    # (`ChunkedDeliveryJob#build_message!`). O que não resolve mais fica fora, com `cartao_descartado` motivo=pagina_mudou;
    # sem nenhum resolvido, a chave sai. Sem referência, a marca como veio.
    def marca_resolvida(marca, agent:, conversation_id:, msg:)
      return marca if marca[NA_ANCORA].blank?

      cartoes, perdidos = resolver(marca[NA_ANCORA], agent)
      descartados(conversation_id: conversation_id, agent: agent.id, msg: msg, motivo: 'pagina_mudou') if perdidos.positive?
      cartoes.empty? ? marca.except(NA_ANCORA) : marca.merge(NA_ANCORA => cartoes)
    end

    # O registro de cartão que não vai sair (só ids e o motivo).
    def descartados(conversation_id:, agent:, msg:, motivo:)
      ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:cartao_descartado, conversation_id: conversation_id, agent: agent,
                                                                                    msg: msg, motivo: motivo)
    end

    # O job dos cartões da âncora recém-postada, quando ela os tem. Erro ao enfileirar não sobe: log com os ids e a
    # classe, tracker e `cartao_nao_enviado` motivo=erro_ao_enfileirar.
    def enfileirar(ancora)
      return if da_ancora(ancora).empty?

      ::Autonomia::Agents::Operate::EnviarCartoesJob.perform_later(ancora.id)
    rescue StandardError => e
      Rails.logger.warn("[autonomia][operate] cartoes_nao_enfileirados conv=#{ancora.conversation_id} msg=#{ancora.id} #{e.class.name}")
      ChatwootExceptionTracker.new(e, account: ancora.account).capture_exception
      ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:cartao_nao_enviado, conversation_id: ancora.conversation_id,
                                                                                     msg: ancora.id, motivo: 'erro_ao_enfileirar')
    end

    # As referências resolvidas pela página do agente agora. -> [os cartões completos, quantos não resolveram].
    def resolver(referencias, agent)
      pagina = NATIVO.pagina(agent)
      completos = Array(referencias).filter_map do |referencia|
        formato = formato_na_pagina(pagina, referencia)
        referencia.slice(*REFERENCIA).merge('rich_message' => formato) if formato
      end
      [completos, Array(referencias).size - completos.size]
    end

    def formato_na_pagina(pagina, referencia)
      case referencia['tipo']
      when 'location' then NATIVO.locais(pagina).find { |local| local['id'] == referencia['chave'] }&.dig('rich_message')
      when 'contact' then NATIVO.contato(pagina) if referencia['chave'] == NATIVO::CHAVE_DO_CONTATO
      end
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
  # nil quando a anterior não está mais na conversa: o cartão não sai.
  def anterior_de(cartao)
    indice = cartoes.index(cartao)
    return @ancora if indice.nil? || indice.zero?

    postada(cartoes[indice - 1]['token'])
  end

  def encerrado?
    @ancora.reload.content_attributes.to_h[ENCERRADOS].present?
  end

  # Grava a desistência na âncora: só esta chave, por merge, direto na coluna (sem callbacks nem `updated_at`).
  def encerrar!(motivo)
    @ancora.with_lock do
      @ancora.update_column(:content_attributes, @ancora.content_attributes.to_h.merge(ENCERRADOS => motivo)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def postado?(cartao)
    postada(cartao['token']).present?
  end

  # Posta o cartão sob o lock da conversa, conferindo de novo que ele não saiu (dois jobs da mesma âncora), que nenhuma
  # pessoa da equipe escreveu depois da âncora e que a conta segue ligada. -> nil quando postou (ou outro job já o
  # postou); senão o motivo de não postar. Erro sobe para quem chama.
  def postar!(cartao)
    @conversation.with_lock do
      motivo = motivo_para_nao_postar
      construir!(cartao) unless motivo || postado?(cartao)
      motivo
    end
  end

  private

  def motivo_para_nao_postar
    return 'pessoa_respondeu' if ::Autonomia::Agents::Operate::PessoaDaEquipe.respondeu_depois?(@conversation, @ancora.id)

    'desligado' unless NATIVO.ligado?(@conversation.account)
  end

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
