# Os motores antigos entram na cadeia comum (#2414 F1, D6): regras de automação e automações de etapa do CRM.
# Cada execução entra como "regra:<id>" ou "etapa:<id>". Com a flag `automacao_fundacao`, a cadeia pode recusar
# (laço ou cascata), e o motivo vai para o registro. Sem a flag, nada entra na cadeia, nada vai para o contexto dos
# jobs, e o motor faz o que fazia. Quem retoma a cadeia guardada confere a flag de novo (rollback).
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
      return super unless Cadeia.vale_para?(@card.account)

      resultado = Cadeia.com("etapa:#{automation.id}", @card.account_id) do
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
      Cadeia.retomar(Cadeia.origens | Array(@automation_context[CHAVE_NO_CONTEXTO]), @card.account) { super }
    end
  end

  module PassoDeEtapa
    def perform(card_id:, automation_context: {}, **)
      cadeia = automation_context.to_h.with_indifferent_access[CHAVE_NO_CONTEXTO]
      return super if cadeia.blank?

      Cadeia.retomar(Cadeia.origens | Array(cadeia), Crm::Card.find_by(id: card_id)&.account) { super }
    end
  end

  # Autonomia::Decisores::PerguntarJob: o passo do Decisor de uma regra sai para um job e, com a resposta, retoma a
  # regra do passo seguinte. A cadeia vai junto no job (inclusive nas novas tentativas), como o contexto vai no
  # PerguntarEtapaJob. A retomada depois de uma pessoa decidir a dúvida começa sem cadeia: a pausa humana a encerra.
  module PerguntaDaRegra
    CHAVE_NO_JOB = 'autonomia_cadeia'.freeze

    def serialize
      cadeia = Cadeia.ativa? ? { 'conta' => Cadeia.conta_id, 'origens' => Cadeia.origens } : @autonomia_cadeia
      cadeia.present? ? super.merge(CHAVE_NO_JOB => cadeia) : super
    end

    def deserialize(job_data)
      super
      @autonomia_cadeia = job_data[CHAVE_NO_JOB]
    end

    def perform(...)
      cadeia = @autonomia_cadeia.to_h
      return super if cadeia.blank?

      Cadeia.retomar(cadeia['origens'], Account.find_by(id: cadeia['conta'])) { super }
    end
  end
end
