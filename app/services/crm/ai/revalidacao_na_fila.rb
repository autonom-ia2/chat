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
# mensagem do cliente ou do atendimento (incoming ou outgoing): nota privada, atividade e os avisos automáticos da caixa
# (saudação, fora do horário, pesquisa, que o Chatwoot grava como `template`) não contam. A última mensagem lida fica
# na marca (`revalidado_ate`, 0 se não havia nenhuma): uma chamada por espera e por mensagem nova, e nunca uma a cada
# rodada de 2 minutos.
#
# Contrato com a fila (revisão do PR #1980): qualquer falha da releitura (IA fora, resposta inválida, erro inesperado)
# entrega como hoje, já nesta rodada, e grava `revalidado_ate` para não pagar outra chamada na rodada seguinte sem
# mensagem nova. Uma resposta que chega velha (a espera, o motivo, o card ou as mensagens mudaram durante a chamada) é
# descartada sem gravar nada, e a conversa espera a rodada seguinte para ser relida.
class Crm::Ai::RevalidacaoNaFila
  # superado: a marca saiu e ninguém recebe. adiar: não entrega nesta rodada (a resposta ficou velha). falhou: a
  # releitura não aconteceu (não conta na cota da rodada) e a entrega segue como antes.
  Resultado = Struct.new(:superado, :adiar, :falhou, :decisao, keyword_init: true)

  # com_trava: a trava de linha de quem chama (HandoffDrainJob#com_lock_timeout); sem ela, a trava sem limite.
  def initialize(conversation, com_trava: ->(&bloco) { bloco.call })
    @conversation = conversation
    @com_trava = com_trava
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
  # mensagem lida e o motivo novo (que vai junto na entrega).
  def call
    marca = Crm::Entrega::Marca.dados(@conversation)
    ultima = ate_onde_reler(marca) if da_ia_do_crm?(marca)
    return Resultado.new(decisao: 'ja_relida') if ultima.nil?

    resposta = reler(marca)
    return falhou!(marca, ultima, resposta) if resposta.is_a?(Exception)

    aplicar(resposta, marca, ultima)
  end

  private

  # Perder o pedido de uma pessoa é pior do que entregar uma conversa à toa: qualquer erro aqui vira entrega.
  def reler(marca)
    Crm::Ai::RevalidaPassagem.new(@conversation, card: card, motivo_do_pedido: marca['razao']).call
  rescue StandardError => e
    e
  end

  def da_ia_do_crm?(marca)
    marca.present? && marca['modo'] == Crm::Entrega::Marca::SEGURANDO &&
      marca['motivo'] == Crm::Ai::HandoffExecutor::MOTIVO_DA_ENTREGA
  end

  def mensagens_reais
    @conversation.messages.where(private: false, message_type: %i[incoming outgoing])
  end

  # Até qual mensagem a reavaliação vai ler, ou nil quando não há o que reler. Espera ainda não relida: a mensagem real
  # mais nova (0 se não há nenhuma). Já relida: a mais nova depois da última leitura, se houver.
  def ate_onde_reler(marca)
    return mensagens_reais.maximum(:id) || 0 if marca['revalidado_ate'].nil?

    mensagens_reais.where('messages.id > ?', marca['revalidado_ate'].to_i).maximum(:id)
  end

  # A resposta vale para a espera que foi lida: a mesma espera, o mesmo motivo, o mesmo card e nenhuma mensagem nova
  # desde a leitura (um pedido explícito que chegou durante a chamada não pode sumir com uma resposta velha).
  def mesma_espera?(atual, marca, ultima)
    da_ia_do_crm?(atual) && atual.values_at('desde', 'razao', 'card_id') == marca.values_at('desde', 'razao', 'card_id') &&
      !mensagens_reais.exists?(['messages.id > ?', ultima])
  end

  # Sob a trava da conversa, relendo a marca. Resposta velha: nada é gravado e a conversa fica para a rodada seguinte.
  def aplicar(resposta, marca, ultima)
    gravou = sob_a_trava(marca, ultima) do
      if resposta[:passa]
        Crm::Entrega::Marca.revalidada!(@conversation, ate: ultima, razao: resposta[:motivo])
      else
        Crm::Entrega::Marca.tirar(@conversation)
      end
      true
    end
    depois_de_aplicar(resposta, gravou ? !resposta[:passa] : nil)
  end

  # A falha não se repete a cada rodada: a marca guarda a última mensagem lida (o motivo segue o do pedido) e só uma
  # mensagem nova pede outra releitura.
  def falhou!(marca, ultima, erro)
    sob_a_trava(marca, ultima) { Crm::Entrega::Marca.revalidada!(@conversation, ate: ultima, razao: nil) }
    registrar('revalidacao_falhou', erro.class.name)
    Resultado.new(falhou: true, decisao: 'falhou')
  end

  # nil quando a espera mudou (nada gravado); senão, o valor do bloco.
  def sob_a_trava(marca, ultima)
    valor = nil
    @com_trava.call do
      @conversation.with_lock do
        next unless mesma_espera?(Crm::Entrega::Marca.dados(@conversation), marca, ultima)

        valor = yield
        @conversation.save! if @conversation.changed?
      end
    end
    valor
  end

  def depois_de_aplicar(resposta, superado)
    atividade!(resposta) if superado
    desfecho, motivo = { true => %w[skipped pedido_superado], false => ['revalidado', resposta[:decisao]],
                         nil => %w[revalidado resposta_velha] }.fetch(superado)
    registrar(desfecho, motivo)
    Resultado.new(superado: superado == true, adiar: superado.nil?, decisao: resposta[:decisao])
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
