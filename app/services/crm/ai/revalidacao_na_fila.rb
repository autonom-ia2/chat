# A fila (Crm::Ai::HandoffDrainJob) confere, antes de entregar, se o pedido de pessoa da IA do CRM ainda está de pé
# (#1975). Caso real: a avaliação da meia-noite pediu uma pessoa por um anúncio do robô que ele mesmo superou; ninguém
# estava online, e a fila entregou a conversa 10 h 30 depois.
#
# Só a espera da IA do CRM (motivo `ia_crm`), segurando. Ficam como estão: a espera que o próprio agente pediu
# (bot_handoff!), a da caixa sem regra, o convite e o convite vencido. O cliente que pede gente depois continua sendo
# atendido: a reavaliação (Crm::Ai::RevalidaPassagem) conta o pedido explícito como "passa", sempre.
#
# Custo: só há o que reler quando chegou mensagem real (do cliente ou do atendimento; nem nota privada, nem atividade,
# nem os avisos automáticos da caixa) depois do começo da espera, ou
# depois da última reavaliação. A última mensagem considerada fica na marca (`revalidado_ate`): uma chamada por marca e
# por mensagem nova, e nunca uma a cada rodada de 2 minutos. Sem mensagem nova, entrega como antes.
class Crm::Ai::RevalidacaoNaFila
  # O que a reavaliação devolveu e foi feito com ele (para o log e o spec).
  Resultado = Struct.new(:superado, :decisao, keyword_init: true)

  def initialize(conversation)
    @conversation = conversation
  end

  # Há o que reler? Barato: só a marca e uma consulta de mensagens. A espera que vai ser largada para um agente nosso
  # (#1673, HandoffDrainJob#largar_para_o_agente) ou espaçada nesta rodada não gasta chamada.
  def precisa?
    marca = Crm::Entrega::Marca.dados(@conversation)
    return false unless da_ia_do_crm?(marca)
    return false if Crm::Entrega::ConviteVencido.espacar?(marca)
    return false if ::Autonomia::Agents::QuemResponde.dono_ativo(@conversation).present?

    ultima_mensagem_nova(marca).present?
  end

  # Reavalia (uma chamada) e aplica: superado, a marca sai, com atividade no card e log; de pé, a marca guarda a última
  # mensagem lida e o motivo novo (que vai junto na entrega). Falhou a reavaliação: segue para a entrega, como antes,
  # porque perder o pedido de uma pessoa é pior do que entregar uma conversa à toa.
  def call
    marca = Crm::Entrega::Marca.dados(@conversation)
    ultima = ultima_mensagem_nova(marca) if da_ia_do_crm?(marca)
    return Resultado.new(superado: false, decisao: 'sem_mensagem_nova') if ultima.blank?

    resposta = Crm::Ai::RevalidaPassagem.new(@conversation, card: card, motivo_do_pedido: marca['razao']).call
    aplicar(resposta, marca, ultima)
  rescue Crm::Ai::RevalidaPassagem::Indisponivel, Crm::Ai::RevalidaPassagem::RespostaInvalida, Crm::Ai::ResponsesClient::Error => e
    registrar('revalidacao_falhou', e.class.name.demodulize.underscore)
    Resultado.new(superado: false, decisao: 'falhou')
  end

  private

  def da_ia_do_crm?(marca)
    marca.present? && marca['modo'] == Crm::Entrega::Marca::SEGURANDO &&
      marca['motivo'] == Crm::Ai::HandoffExecutor::MOTIVO_DA_ENTREGA
  end

  # A mensagem real mais nova depois do começo da espera (ou da última reavaliação), ou nil.
  def ultima_mensagem_nova(marca)
    mensagens = @conversation.messages.where(private: false, message_type: %i[incoming outgoing])
    mensagens = if marca['revalidado_ate'].present?
                  mensagens.where('messages.id > ?', marca['revalidado_ate'].to_i)
                else
                  desde = Crm::Entrega::Marca.desde(@conversation)
                  return if desde.blank?

                  mensagens.where('messages.created_at > ?', desde)
                end
    mensagens.maximum(:id)
  end

  # Sob a trava da conversa, relendo a marca: se ela mudou no meio (outra entrega, uma pessoa assumiu, um pedido novo
  # do agente), a resposta é sobre uma espera que já não existe e nada é gravado.
  def aplicar(resposta, marca, ultima)
    superado = nil
    @conversation.with_lock do
      atual = Crm::Entrega::Marca.dados(@conversation)
      next unless da_ia_do_crm?(atual) && atual['desde'] == marca['desde']

      superado = !resposta[:passa]
      if superado
        Crm::Entrega::Marca.tirar(@conversation)
      else
        Crm::Entrega::Marca.revalidada!(@conversation, ate: ultima, razao: resposta[:motivo])
      end
      @conversation.save! if @conversation.changed?
    end
    depois_de_aplicar(resposta, superado)
  end

  # superado nil: a marca mudou durante a reavaliação, e nada foi gravado.
  def depois_de_aplicar(resposta, superado)
    atividade!(resposta) if superado
    desfecho, motivo = { true => %w[skipped pedido_superado], false => ['revalidado', resposta[:decisao]],
                         nil => %w[revalidado marca_mudou] }.fetch(superado)
    registrar(desfecho, motivo)
    Resultado.new(superado: superado == true, decisao: resposta[:decisao])
  end

  def card
    @card ||= Crm::Entrega::Marca.card(@conversation) || Crm::Assunto.funil_atual(@conversation)
  end

  # O porquê fica no card (a equipe vê na linha do tempo); o log leva só ids e rótulos.
  def atividade!(resposta)
    Crm::ActivityLogger.new(
      card: card, actor: nil, event_type: 'ai_handoff_withdrawn', conversation: @conversation,
      payload: { reason: resposta[:motivo].to_s.first(300), decision: resposta[:decisao] }
    ).perform
  end

  def registrar(desfecho, motivo)
    Rails.logger.info("[crm][handoff] card=#{card&.id || '-'} conversa=#{@conversation.id} gatilho=fila " \
                      "desfecho=#{desfecho} motivo=#{motivo}")
  end
end
