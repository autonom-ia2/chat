# Roda os passos de uma automação de etapa, em ordem, e fecha a execução (completed/failed).
#
# O passo `perguntar_ao_decisor` (#858) não roda aqui: o Jev leva de centenas de milissegundos a
# segundos, e mover um card acontece dentro da requisição. O passo vai para um job, a execução fica
# esperando (metadata `decisor`) e os passos seguintes só rodam lá, se o Decisor responder a chave
# combinada. O job usa esta mesma classe para os passos que sobraram.
class Crm::StageAutomations::StepSequence
  def initialize(card:, actor:, execution:, automation_context: {})
    @card = card
    @actor = actor
    @execution = execution
    @automation_context = automation_context.to_h.with_indifferent_access
  end

  def perform(steps, step_results = [])
    steps.each do |step|
      return esperar_decisor(step, step_results) if step.perguntar_ao_decisor?

      result = run_step(step)
      step_results << { step_id: step.id, status: result.status, error: result.error, payload: result.payload }
      next if result.status == :ok

      return finish(:failed, step_results, result.error.to_s)
    end

    finish(:completed, step_results)
  end

  private

  def run_step(step)
    return enqueue_delayed_step(step) if step.delay_seconds.positive? && step.action_type != 'create_follow_up'

    Crm::StageAutomations::StepExecutor.new(card: @card.reload, step: step, actor: @actor, automation_context: @automation_context).perform
  end

  def enqueue_delayed_step(step)
    Crm::StageAutomationStepJob.set(wait: step.delay_seconds.seconds).perform_later(
      card_id: @card.id, step_id: step.id, actor_id: @actor&.id, execution_id: @execution.id, automation_context: @automation_context
    )
    Crm::StageAutomations::StepExecutor::Result.ok(scheduled: true)
  end

  def esperar_decisor(step, step_results)
    espera = { 'step_id' => step.id, 'actor_id' => @actor&.id, 'automation_context' => @automation_context.to_h }
    @execution.update!(metadata: @execution.metadata.merge('step_results' => step_results, 'decisor' => espera))
    Autonomia::Decisores::PerguntarEtapaJob.set(wait: step.delay_seconds.seconds).perform_later(@execution.id, step.id)
  end

  def finish(status, step_results, error_message = nil)
    @execution.update!(status: status, error_message: error_message, completed_at: Time.current,
                       metadata: @execution.metadata.merge('step_results' => step_results))
  end
end
