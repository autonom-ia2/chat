# A fila (Crm::Ai::HandoffDrainJob) confere, antes de entregar, se o pedido de pessoa da IA do CRM ainda está de pé
# (#1975). Caso real: a avaliação da meia-noite pediu uma pessoa por um anúncio do robô que ele mesmo superou; ninguém
# estava online, e a fila entregou a conversa 10 h 30 depois.
#
# Só a espera da IA do CRM (motivo `ia_crm`), segurando, num funil com a IA ligada. Ficam como estão: a espera que o
# próprio agente pediu (bot_handoff!), a da caixa sem regra, o convite e o convite vencido. O cliente que pede gente
# depois continua sendo atendido: a reavaliação (Crm::Ai::RevalidaPassagem) conta o pedido explícito como "passa".
#
# Quando: toda espera é relida uma vez antes da entrega, mesmo sem mensagem nova, porque a decisão foi tomada no meio
# da conversa e a espera dura horas (a avaliação da meia-noite errou e nada chegou depois). Depois, só se chegar
# mensagem do cliente ou do atendimento (incoming ou outgoing): nota privada, atividade e os avisos automáticos da caixa
# (saudação, fora do horário, pesquisa, que o Chatwoot grava como `template`) não contam. A última mensagem lida fica
# na marca (`revalidado_ate`, 0 se não havia nenhuma): uma chamada por espera e por mensagem nova.
#
# Onde (backteste do PR #1980: p50 20 s, máximo 74 s): a chamada não cabe na rodada da fila, então roda num job
# (Crm::Ai::RevalidaPassagemJob). A fila (#segurar?) só grava a releitura em curso na marca e enfileira, um job por
# espera; enquanto ela não termina, a conversa fica na espera. O job (#reler!) toma a execução para si sob a trava
# (um segundo job do mesmo token sai sem chamar), chama a IA e aplica, também sob a trava: resolvido, a marca sai;
# aberto, a marca guarda a última mensagem lida e o motivo novo, e a rodada seguinte entrega; falhou (na chamada ou ao
# aplicar), a marca guarda a última mensagem lida e `revalidacao_falhou`, e a rodada seguinte entrega como hoje.
# Resposta velha (a espera, o motivo, o card ou as mensagens mudaram durante a chamada) é descartada, e a rodada
# seguinte enfileira outra. Prazo total (`revalidacao_comecou_em`, que sobrevive ao descarte e ao reenfileiramento):
# passando de 10 min, a fila entrega como hoje, mesmo com mensagens chegando a cada releitura; o job vencido não chama
# a IA nem aplica. Job que parece perdido (5 min sem resposta) é enfileirado de novo uma vez.
class Crm::Ai::RevalidacaoNaFila
  REENFILEIRAR_DEPOIS = 5.minutes
  VENCE_DEPOIS = 10.minutes

  # com_trava: a trava de linha de quem chama (HandoffDrainJob#com_lock_timeout); sem ela, a trava sem limite.
  def initialize(conversation, com_trava: ->(&bloco) { bloco.call })
    @conversation = conversation
    @com_trava = com_trava
  end

  # Para a fila: true segura a conversa nesta rodada (a releitura foi enfileirada ou segue em curso); false segue para
  # a entrega (não é espera da IA do CRM, não há o que reler, ou a releitura venceu).
  def segurar?
    marca = Crm::Entrega::Marca.dados(@conversation)
    return false unless releitura_cabe?(marca)
    return vencida!(marca) if vencida?(marca)
    return em_curso!(marca) if marca['revalidando_desde'].present?
    return false if ate_onde_reler(marca).nil?

    enfileirar!(marca)
    true
  end

  # Para o job: relê a espera enfileirada com `token` (o `revalidando_desde` da marca) e aplica. Job de uma releitura
  # que já não existe, que outro job já tomou, ou cujo prazo total venceu não chama a IA.
  def reler!(token)
    marca = tomar!(token)
    return if marca.nil?

    ultima = ate_onde_reler(marca) || marca['revalidado_ate'].to_i
    resposta = reler(marca)
    return falhou!(ultima, token, resposta) if resposta.is_a?(Exception)

    aplicar(resposta, marca, ultima, token)
  rescue StandardError => e
    # Falhou ao aplicar, depois da resposta: a rodada seguinte entrega como hoje.
    falhou!(ultima, token, e) if marca && ultima
  end

  private

  # A espera que vai ser largada para um agente nosso (#1673, HandoffDrainJob#largar_para_o_agente) ou espaçada nesta
  # rodada não gasta chamada. Com a IA do CRM desligada, na instalação ou no funil do card (a mesma regra da avaliação
  # do card), a releitura não acontece: entrega como hoje, sem esperar o job.
  def releitura_cabe?(marca)
    Crm::Ai::Config.enabled? && da_ia_do_crm?(marca) && card.present? && Crm::Ai::Config.pipeline_ai_enabled?(card.pipeline) &&
      !Crm::Entrega::ConviteVencido.espacar?(marca) && ::Autonomia::Agents::QuemResponde.dono_ativo(@conversation).blank?
  end

  def da_ia_do_crm?(marca)
    marca.present? && marca['modo'] == Crm::Entrega::Marca::SEGURANDO &&
      marca['motivo'] == Crm::Ai::HandoffExecutor::MOTIVO_DA_ENTREGA
  end

  def vencida?(marca)
    comecou = marca['revalidacao_comecou_em'].presence
    comecou.present? && Time.current - Time.zone.parse(comecou) > VENCE_DEPOIS
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

  def agora = Time.current.utc.iso8601(6)

  # O prazo total começa na primeira releitura desta espera e não recomeça a cada job.
  def enfileirar!(marca)
    token = agora
    gravou = sob_a_trava do |atual|
      next false unless atual['desde'] == marca['desde'] && atual['revalidando_desde'].blank?

      Crm::Entrega::Marca.revalidando!(@conversation, 'revalidando_desde' => token,
                                                      'revalidacao_comecou_em' => atual['revalidacao_comecou_em'] || token)
      true
    end
    Crm::Ai::RevalidaPassagemJob.perform_later(@conversation.id, token) if gravou
  end

  # Releitura em curso: segura; sem resposta em 5 min (e sem job tendo tomado a execução), enfileira de novo uma vez.
  def em_curso!(marca)
    idade = Time.current - Time.zone.parse(marca['revalidando_desde'])
    reenfileirar!(marca) if idade > REENFILEIRAR_DEPOIS && marca['reenfileirado_em'].blank? &&
                            marca['revalidacao_iniciada_em'].blank?
    true
  end

  def reenfileirar!(marca)
    token = marca['revalidando_desde']
    gravou = sob_a_trava do |atual|
      next false unless atual['revalidando_desde'] == token

      Crm::Entrega::Marca.revalidando!(@conversation, 'reenfileirado_em' => agora)
      true
    end
    Crm::Ai::RevalidaPassagemJob.perform_later(@conversation.id, token) if gravou
  end

  # Prazo total vencido: entrega como hoje, com o pedido e o motivo atuais, e a marca guarda a última mensagem para não
  # reler de novo sem mensagem nova.
  def vencida!(marca)
    ultima = ate_onde_reler(marca) || marca['revalidado_ate'].to_i
    sob_a_trava do |atual|
      next unless atual['revalidacao_comecou_em'] == marca['revalidacao_comecou_em']

      Crm::Entrega::Marca.revalidada!(@conversation, ate: ultima, razao: nil, falhou: true)
    end
    registrar('revalidacao_vencida', 'prazo_total_10_min')
    false
  end

  # Sob a trava: a releitura é deste token, ninguém a tomou ainda e o prazo total não venceu. Devolve a marca (agora
  # com `revalidacao_iniciada_em`) ou nil, e aí o job sai sem chamar a IA.
  def tomar!(token)
    sob_a_trava do |atual|
      next if atual['revalidando_desde'] != token || atual['revalidacao_iniciada_em'].present? || vencida?(atual)

      Crm::Entrega::Marca.revalidando!(@conversation, 'revalidacao_iniciada_em' => agora)
      Crm::Entrega::Marca.dados(@conversation)
    end
  end

  # Perder o pedido de uma pessoa é pior do que entregar uma conversa à toa: qualquer erro aqui vira entrega.
  def reler(marca)
    Crm::Ai::RevalidaPassagem.new(@conversation, card: card, motivo_do_pedido: marca['razao'], desde_do_pedido: marca['desde']).call
  rescue StandardError => e
    e
  end

  # A resposta vale para a espera que foi lida: a mesma releitura, dentro do prazo total, a mesma espera, o mesmo
  # motivo, o mesmo card e nenhuma mensagem nova desde a leitura (um pedido explícito que chegou durante a chamada não
  # pode sumir com uma resposta velha).
  def mesma_espera?(atual, marca, ultima, token)
    atual['revalidando_desde'] == token && !vencida?(atual) &&
      atual.values_at('desde', 'razao', 'card_id') == marca.values_at('desde', 'razao', 'card_id') &&
      !mensagens_reais.exists?(['messages.id > ?', ultima])
  end

  # Sob a trava da conversa, relendo a marca. Resposta velha: nada é gravado além de tirar o job em curso (a rodada
  # seguinte enfileira outro, dentro do mesmo prazo total).
  def aplicar(resposta, marca, ultima, token)
    gravou = sob_a_trava do |atual|
      next descartar!(atual, token) unless mesma_espera?(atual, marca, ultima, token)

      if resposta[:passa]
        Crm::Entrega::Marca.revalidada!(@conversation, ate: ultima, razao: resposta[:motivo])
      else
        Crm::Entrega::Marca.tirar(@conversation)
      end
      true
    end
    depois_de_aplicar(resposta, gravou ? !resposta[:passa] : nil)
  end

  # A falha não se repete: a marca guarda a última mensagem lida (o motivo segue o do pedido) e só uma mensagem nova
  # pede outra releitura. A rodada seguinte entrega como hoje.
  def falhou!(ultima, token, erro)
    sob_a_trava do |atual|
      next descartar!(atual, token) unless atual['revalidando_desde'] == token

      Crm::Entrega::Marca.revalidada!(@conversation, ate: ultima, razao: nil, falhou: true)
    end
    registrar('revalidacao_falhou', erro.class.name)
  end

  def descartar!(atual, token)
    Crm::Entrega::Marca.sem_releitura!(@conversation) if atual['revalidando_desde'] == token
    false
  end

  # O valor do bloco (que recebe a marca atual, já sob a trava), ou nil quando a marca já não é da IA do CRM.
  def sob_a_trava
    valor = nil
    @com_trava.call do
      @conversation.with_lock do
        atual = Crm::Entrega::Marca.dados(@conversation)
        next unless da_ia_do_crm?(atual)

        valor = yield atual
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
