# A fila (Crm::Ai::HandoffDrainJob) confere, antes de entregar, se o pedido de pessoa da IA do CRM ainda está de pé
# (#1975). Caso real: a avaliação da meia-noite pediu uma pessoa por um anúncio do robô que ele mesmo superou; ninguém
# estava online, e a fila entregou a conversa 10 h 30 depois.
#
# Só a espera da IA do CRM (motivo `ia_crm`), segurando. Ficam como estão: a espera que o próprio agente pediu
# (bot_handoff!), a da caixa sem regra, o convite e o convite vencido. O cliente que pede gente depois continua sendo
# atendido: a reavaliação (Crm::Ai::RevalidaPassagem) conta o pedido explícito como "passa", sempre.
#
# Quando: toda espera é relida uma vez antes da entrega, mesmo sem mensagem nova, porque a decisão foi tomada no meio
# da conversa e a espera dura horas (a avaliação da meia-noite errou e nada chegou depois). Depois, só se chegar
# mensagem real (do cliente ou do atendimento; nem nota privada, nem atividade, nem os avisos automáticos da caixa).
# A última mensagem lida fica na marca (`revalidado_ate`, 0 se não havia nenhuma): uma chamada por espera e por
# mensagem nova, e nunca uma a cada rodada de 2 minutos.
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

    !ate_onde_reler(marca).nil?
  end

  # Reavalia (uma chamada) e aplica: superado, a marca sai, com atividade no card e log; de pé, a marca guarda a última
  # mensagem lida e o motivo novo (que vai junto na entrega). Falhou a reavaliação: segue para a entrega, como antes,
  # porque perder o pedido de uma pessoa é pior do que entregar uma conversa à toa.
  def call
    marca = Crm::Entrega::Marca.dados(@conversation)
    ultima = ate_onde_reler(marca) if da_ia_do_crm?(marca)
    return Resultado.new(superado: false, decisao: 'ja_relida') if ultima.nil?

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

  # Até qual mensagem a reavaliação vai ler, ou nil quando não há o que reler. Espera ainda não relida: a mensagem real
  # mais nova (0 se não há nenhuma). Já relida: a mais nova depois da última leitura, se houver.
  def ate_onde_reler(marca)
    mensagens = @conversation.messages.where(private: false, message_type: %i[incoming outgoing])
    return mensagens.maximum(:id) || 0 if marca['revalidado_ate'].nil?

    mensagens.where('messages.id > ?', marca['revalidado_ate'].to_i).maximum(:id)
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
