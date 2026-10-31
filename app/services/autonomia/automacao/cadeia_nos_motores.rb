# Os motores antigos entram na cadeia comum (#2414 F1, D6): regras de automação e automações de etapa do CRM.
# Cada execução entra como "regra:<id>" ou "etapa:<id>". Com a flag `automacao_fundacao`, a cadeia pode recusar
# (laço ou cascata), e o motivo vai para o registro. Sem a flag, a entrada só anota, e o motor faz o que fazia.
module Autonomia::Automacao::CadeiaNosMotores
  Cadeia = Autonomia::Automacao::Cadeia
  CHAVE_NO_CONTEXTO = 'cadeia'.freeze

  # AutomationRules::ActionService: a regra inteira roda dentro da cadeia, inclusive o que ela chamar de forma
  # síncrona (mover o card dispara as automações de etapa ali mesmo).
  module Regra
    def perform(...)
      resultado = Cadeia.entrar("regra:#{@rule.id}", @account) { super }
      return resultado unless resultado.is_a?(Cadeia::Recusa)

      Cadeia.registrar_recusa(resultado, account_id: @account.id, alvo: "conversa:#{@conversation.id}")
      nil
    end
  end

  # Crm::StageAutomations::Runner: cada automação da etapa entra na cadeia. A lista vai no contexto, porque os passos
  # com atraso e a volta do Decisor rodam em job.
  module Etapa
    private

    def run_automation(automation, stage_id, trigger_event)
      resultado = Cadeia.entrar("etapa:#{automation.id}", @card.account) do
        @automation_context = @automation_context.merge(CHAVE_NO_CONTEXTO => Cadeia.origens)
        super
      end
      return resultado unless resultado.is_a?(Cadeia::Recusa)

      Cadeia.registrar_recusa(resultado, account_id: @card.account_id, alvo: "card:#{@card.id}")
      nil
    end
  end

  # Crm::StageAutomations::StepSequence e Crm::StageAutomationStepJob: retomam a cadeia guardada no contexto.
  module SequenciaDeEtapa
    def perform(...)
      Cadeia.restaurada(Cadeia.origens | Array(@automation_context[CHAVE_NO_CONTEXTO])) { super }
    end
  end

  module PassoDeEtapa
    def perform(automation_context: {}, **)
      cadeia = automation_context.to_h.with_indifferent_access[CHAVE_NO_CONTEXTO]
      Cadeia.restaurada(Cadeia.origens | Array(cadeia)) { super }
    end
  end
end
