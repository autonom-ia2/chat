# O passo `perguntar_ao_decisor` de uma automação de etapa do CRM (#858): o mesmo contrato do passo da
# regra de automação (PerguntarJob), com o card como alvo.
#
# O Decisor lê o card e o que vem com ele (contato, empresa, a conversa em atendimento, se houver).
# A decisão é única por (decisor, card, gatilho da etapa): duas automações da mesma etapa com o mesmo
# Decisor pagam uma pergunta. Resposta combinada, com certeza suficiente: grava os campos e roda os
# passos que sobraram. Outra resposta: a execução termina ali. Dúvida: vai ao Guia, e a execução fica
# esperando — quando a dúvida se resolve, a Retomada volta aqui com `retomada`, e o card tem de estar
# ainda onde a automação o pegou (aberto e na etapa, na entrada; fora dela, na saída).
class Autonomia::Decisores::PerguntarEtapaJob < ApplicationJob
  queue_as :medium

  retry_on Autonomia::Decisores::PerguntarJob::JevIndisponivel, wait: 1.minute, attempts: 3 do |job, error|
    Rails.logger.warn("[autonomia][decisor] execucao=#{job.arguments.first} Jev indisponível, desisti: #{error.message}")
  end

  def perform(execution_id, step_id, retomada = false) # rubocop:disable Style/OptionalBooleanParameter
    return unless Crm::Config.enabled?

    @execution = Crm::StageAutomationExecution.find_by(id: execution_id)
    @step = @execution && Crm::StageAutomationStep.find_by(id: step_id, stage_automation_id: @execution.stage_automation_id)
    return unless esperando?

    decisor = Autonomia::Decisor.find_by(id: config['decisor_id'].to_s, account_id: @execution.account_id)
    return if decisor.blank?

    @retomada = retomada
    decidir(decisor)
  end

  private

  # O passo continua sendo o do Decisor, a automação ligada e a execução ainda esperando.
  def esperando?
    @step&.perguntar_ao_decisor? && @step.stage_automation.enabled? && @execution.running?
  end

  def decidir(decisor)
    marca = { 'etapa' => @step.id, 'execucao' => @execution.id }
    decisao = perguntar(decisor, marca)
    return if decisao.parada?
    return terminar(decisao) unless segue?(decisao)
    return terminar(decisao, 'o card mudou de lugar enquanto esperava') if @retomada && !card_no_lugar?

    seguir(decisao, marca)
  rescue TypesafeAi::Decisor::Error => e
    raise Autonomia::Decisores::PerguntarJob::JevIndisponivel, e.code if Autonomia::Decisores::PerguntarJob::TRANSITORIOS.include?(e.code)

    Rails.logger.warn("[autonomia][decisor] execucao=#{@execution.id} decisor=#{decisor.id} Jev recusou: #{e.code}")
  end

  def segue?(decisao)
    decisao.decidida? && decisao.resposta == config['chave_que_segue'].to_s
  end

  def perguntar(decisor, marca)
    Autonomia::Decisores::Pergunta.new(decisor: decisor, card: card, conversation: card.conversa_em_atendimento,
                                       gatilho: @execution.trigger_token, espera: marca).decisao.aguardar!(marca)
  end

  def card
    @card ||= @execution.card
  end

  def seguir(decisao, marca)
    estado = Autonomia::Decisores::Estado.new(card: card, conversation: decisao.conversation, leituras: decisao.decisor.leituras_efetivas)
    Autonomia::Decisores::Seguimento.new(decisao: decisao, marca: marca, estado: estado).perform do
      Crm::StageAutomations::StepSequence.new(card: card, actor: ator, execution: @execution, automation_context: espera['automation_context'])
                                         .perform(restantes, resultados(decisao))
    end
  end

  # Outra resposta, sem cota, sem nada para ler, ou o card saiu do lugar: a execução termina sem os passos seguintes.
  def terminar(decisao, motivo = nil)
    @execution.update!(status: :completed, completed_at: Time.current,
                       metadata: @execution.metadata.merge('step_results' => resultados(decisao, parou: motivo || true)))
  end

  def resultados(decisao, parou: nil)
    Array(@execution.metadata.to_h['step_results']) +
      [{ step_id: @step.id, status: :ok, payload: { decisor: decisao.status, resposta: decisao.resposta, parou: parou }.compact }]
  end

  # A reconferência da retomada: a automação de entrada só segue com o card aberto e na etapa; a de saída,
  # com o card fora dela.
  def card_no_lugar?
    automacao = @step.stage_automation
    card.reload.open? && (automacao.on_enter? ? card.stage_id == automacao.stage_id : card.stage_id != automacao.stage_id)
  end

  def restantes
    passos = @step.stage_automation.steps.ordered.to_a
    passos.drop(passos.index(@step).to_i + 1)
  end

  def config
    @step.action_config.to_h.stringify_keys
  end

  def espera
    @execution.metadata.to_h['decisor'].to_h
  end

  def ator
    User.find_by(id: espera['actor_id']) if espera['actor_id'].present?
  end
end
