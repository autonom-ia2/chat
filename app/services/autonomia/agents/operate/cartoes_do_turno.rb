# O MAPA E O CARTÃO DE CONTATO DO TURNO (#1479 F3): cada cartão que `enviar_localizacao` e `enviar_contato` marcaram
# (`Delivery#cartoes`) sai numa mensagem própria, DEPOIS da mensagem âncora do turno e só quando ela saiu para o canal.
#
# A ÂNCORA GRAVA OS CARTÕES (`autonomia_cartoes`: tipo, chave, rich_message e token), na hora em que é postada:
#   - clássico: a mensagem de texto (`Responder#post_reply!`);
#   - voz: o áudio, que também grava a interação do turno (`InteracaoDepoisDoAudio`): ela sai pelo mesmo job, antes dos
#     cartões, e o primeiro cartão espera ela sair;
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
# O COMPARATIVO DO SEGURO VIAGEM (#3223, `SeguroViagem::EntregaDoComparativo`) é um cartão deste mesmo caminho: sai depois
# da âncora, com o token e os descartes de sempre, mas não é formato (`rich_message` nil) nem depende da flag do mapa e do
# contato: na hora de postar vira o PDF da cotação, anexado. Nos pedaços ele resolve pela cotação, não pela página.
# O VOUCHER DO SEGURO VIAGEM (#3246, `SeguroViagem::EntregaDoVoucher`) segue as mesmas regras do comparativo, com uma
# diferença: o PDF vem da Universal pela rede, e é baixado fora do lock da conversa (`voucher!`).
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
  COMPARATIVO = ::Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo
  VOUCHER = ::Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher
  # Os cartões do Seguro Viagem: sem formato, resolvidos pela cotação da conversa.
  DO_SEGURO_VIAGEM = [COMPARATIVO, VOUCHER].freeze

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

    # O job dos cartões da âncora recém-postada, quando ela tem o que enviar. Erro ao enfileirar não sobe: log com os ids
    # e a classe, tracker e `cartao_nao_enviado` motivo=erro_ao_enfileirar.
    def enfileirar(ancora)
      return unless algo_a_enviar?(ancora)

      job_da(ancora).perform_later(ancora.id)
    rescue StandardError => e
      Rails.logger.warn("[autonomia][operate] cartoes_nao_enfileirados conv=#{ancora.conversation_id} msg=#{ancora.id} #{e.class.name}")
      ChatwootExceptionTracker.new(e, account: ancora.account).capture_exception
      ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:cartao_nao_enviado, conversation_id: ancora.conversation_id,
                                                                                     msg: ancora.id, motivo: 'erro_ao_enfileirar')
    end

    # As referências resolvidas pela página do agente agora (o contato, com o telefone do agente primeiro, como
    # `enviar_contato`); o comparativo e o voucher, sem formato (o PDF nasce ao postar). -> [os cartões completos,
    # quantos não resolveram].
    def resolver(referencias, agent)
      pagina = NATIVO.pagina(agent)
      completos = Array(referencias).filter_map do |referencia|
        next referencia.slice(*REFERENCIA).merge('rich_message' => nil) if do_seguro_viagem(referencia)

        formato = formato_na_pagina(agent, pagina, referencia)
        referencia.slice(*REFERENCIA).merge('rich_message' => formato) if formato
      end
      [completos, Array(referencias).size - completos.size]
    end

    def formato_na_pagina(agent, pagina, referencia)
      case referencia['tipo']
      when 'location' then NATIVO.locais(pagina).find { |local| local['id'] == referencia['chave'] }&.dig('rich_message')
      when 'contact' then NATIVO.contato_do_agente(agent, pagina) if referencia['chave'] == NATIVO::CHAVE_DO_CONTATO
      end
    end

    # A classe do cartão do Seguro Viagem (`DO_SEGURO_VIAGEM`), ou nil.
    def do_seguro_viagem(cartao)
      DO_SEGURO_VIAGEM.find { |entrega| entrega.cartao?(cartao) }
    end

    def token(turno, cartao)
      "#{turno}:cartao:#{cartao['tipo']}:#{cartao['chave']}"
    end

    def da_ancora(message)
      Array(message&.content_attributes.to_h[NA_ANCORA]).select { |cartao| cartao.is_a?(Hash) && cartao['token'].present? }
    end

    # O job da âncora: a que gravou a interação depois do áudio vai pela `EnviarInteracaoJob` (o worker antigo, no
    # deploy, não a conhece e o Sidekiq refaz o job), as outras pela `EnviarCartoesJob`.
    def job_da(ancora)
      if ::Autonomia::Agents::Operate::InteracaoDepoisDoAudio.da_ancora(ancora).present?
        ::Autonomia::Agents::Operate::EnviarInteracaoJob
      else
        ::Autonomia::Agents::Operate::EnviarCartoesJob
      end
    end

    # A mensagem leva cartões ou a interação depois do áudio (`InteracaoDepoisDoAudio`)?
    def algo_a_enviar?(message)
      da_ancora(message).any? || ::Autonomia::Agents::Operate::InteracaoDepoisDoAudio.da_ancora(message).present?
    end

    # A âncora já postada deste turno (a resposta do robô à mensagem do cliente que leva os cartões ou a interação depois
    # do áudio), ou nil. Prefiltra por LIKE (chaves distintivas) e confirma no hash, como `ChunkedDeliveryJob#chunk_posted?`.
    def ancora_do_turno(conversation, reply_to_message_id)
      return if reply_to_message_id.blank?

      conversation.messages.outgoing.where(sender_type: 'AgentBot')
                  .where('content_attributes::text LIKE ? OR content_attributes::text LIKE ?', "%#{NA_ANCORA}%",
                         "%#{::Autonomia::Agents::Operate::InteracaoDepoisDoAudio::NA_ANCORA}%").reorder(:id)
                  .select { |message| message.content_attributes.to_h['autonomia_reply_to_message_id'].to_s == reply_to_message_id.to_s }
                  .reverse.find { |message| algo_a_enviar?(message) }
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
    return voucher!(cartao) if VOUCHER.cartao?(cartao)

    @conversation.with_lock do
      motivo = motivo_para_nao_postar(cartao)
      construir!(cartao) unless motivo || postado?(cartao)
      motivo
    end
  end

  private

  # O VOUCHER (#3246) é baixado FORA do lock da conversa: a Universal (até 15 s) e o download (até 20 s) não seguram a
  # conversa. As guardas são conferidas antes, sem lock (para não baixar à toa), e de novo sob ele (`anexar_voucher`),
  # como nos outros cartões. Falha da Universal ou do download: a nota da equipe já saiu, e o motivo é `voucher_nao_saiu`.
  def voucher!(cartao)
    impedimento = motivo_para_nao_postar(cartao)
    return impedimento if impedimento || postado?(cartao)

    entrega = VOUCHER.new(conversation: @conversation, cotacao: VOUCHER.cotacao_do(cartao, @conversation),
                          sender_id: @ancora.sender_id, atributos: atributos_do(cartao))
    blob = entrega.baixar
    blob.nil? ? VOUCHER::NAO_SAIU : anexar_voucher(entrega, blob, cartao)
  end

  # Sob o lock da conversa: confere as guardas de novo e cria a mensagem. O PDF que não virou mensagem (a guarda mudou
  # durante o download, erro ao criar) vai para a limpeza.
  def anexar_voucher(entrega, blob, cartao)
    anexado = nil
    @conversation.with_lock do
      impedimento = motivo_para_nao_postar(cartao)
      anexado = entrega.criar(blob) unless impedimento || postado?(cartao)
      impedimento
    end
  ensure
    ::Autonomia::Agents::Tools::EntregaDeArquivo.agendar_limpeza(blob, contexto: 'voucher') if anexado.nil?
  end

  def motivo_para_nao_postar(cartao)
    return 'pessoa_respondeu' if ::Autonomia::Agents::Operate::PessoaDaEquipe.respondeu_depois?(@conversation, @ancora.id)

    entrega = self.class.do_seguro_viagem(cartao)
    return motivo_do_seguro_viagem(entrega, cartao) if entrega

    'desligado' unless NATIVO.ligado?(@conversation.account)
  end

  # O comparativo e o voucher não dependem da flag do mapa e do contato: só dos agentes ligados na conta e da cotação na
  # conversa (apagada com ela, não sai).
  def motivo_do_seguro_viagem(entrega, cartao)
    return 'desligado' unless ::Autonomia::Agents::Config.enabled?(@conversation.account)

    'cotacao_sumiu' if entrega.cotacao_do(cartao, @conversation).nil?
  end

  # O que o cartão do Seguro Viagem grava na mensagem: o agente e o token do turno.
  def atributos_do(cartao)
    { 'autonomia_agent_id' => @ancora.content_attributes.to_h['autonomia_agent_id'], TOKEN => cartao['token'] }
  end

  def construir!(cartao)
    return comparativo!(cartao) if COMPARATIVO.cartao?(cartao)

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

  # O PDF da cotação, anexado, com o agente e o token do turno (`EntregaDoComparativo`).
  def comparativo!(cartao)
    COMPARATIVO.new(conversation: @conversation, cotacao: COMPARATIVO.cotacao_do(cartao, @conversation), sender_id: @ancora.sender_id,
                    atributos: atributos_do(cartao)).postar!
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
