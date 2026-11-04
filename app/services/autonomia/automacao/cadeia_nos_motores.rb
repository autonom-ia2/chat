# Os motores antigos entram na cadeia comum (#2414 F1, D6): regras de automação e automações de etapa do CRM.
# Cada execução entra como "regra:<id>" ou "etapa:<id>". Com a flag `automacao_fundacao`, a cadeia pode recusar
# (laço ou cascata), e o motivo vai para o registro. Sem a flag, nada entra na cadeia, nada vai para o contexto dos
# jobs, e o motor faz o que fazia. Quem retoma a cadeia guardada confere a flag de novo (rollback).
module Autonomia::Automacao::CadeiaNosMotores
  Cadeia = Autonomia::Automacao::Cadeia
  CHAVE_NO_CONTEXTO = 'cadeia'.freeze
  CHAVE_DA_RAIZ = 'cadeia_raiz'.freeze

  # AutomationRules::ActionService: a regra inteira roda dentro da cadeia, inclusive o que ela chamar de forma
  # síncrona (mover o card dispara as automações de etapa ali mesmo).
  module Regra
    def perform(desde: 0, **opcoes)
      origem = "regra:#{@rule.id}"
      # A volta do Decisor (desde > 0) continua a execução que já está na cadeia: não é a regra entrando de novo.
      return super if desde.positive? && Cadeia.origens.include?(origem)

      resultado = Cadeia.entrar(origem, @account) { super }
      return resultado unless resultado.is_a?(Cadeia::Recusa)

      recusar(resultado)
    end

    private

    # Recusada, a regra não roda, nem o `ensure Current.reset` dela: o Current que o initialize preencheu não pode
    # seguir para os próximos listeners do mesmo evento.
    def recusar(recusa)
      Current.reset
      Cadeia.registrar_recusa(recusa, account_id: @account.id, alvo: "conversa:#{@conversation.id}",
                                      conversa: @conversation, nome: @rule.name)
      nil
    end
  end

  # AutomationRuleListener: hoje uma regra nunca dispara outra (o evento com `performed_by` igual a uma regra é
  # ignorado). Com a flag, a mudança feita por uma regra dispara as outras, e quem segura laço e cascata é a cadeia,
  # que veio com o evento. Cadeia ativa aqui implica a flag: `retomar` só a devolve para a conta que tem.
  # A regra com atraso fica de fora: ela roda depois, num job sem a cadeia, e um laço entre duas regras com atraso não
  # teria quem o parasse. Disparada por outra regra, ela segue ignorada, como hoje.
  module RegraDisparaRegra
    thread_mattr_accessor :vinda_de_regra, instance_accessor: false

    def message_created(event)
      pelo_evento(event) { super }
    end

    private

    def process_conversation_event(event, event_name)
      pelo_evento(event) { super }
    end

    # Guarda, enquanto o evento é tratado, se ele veio de uma regra dentro da cadeia: só esse caso é novo.
    def pelo_evento(event)
      anterior = RegraDisparaRegra.vinda_de_regra
      RegraDisparaRegra.vinda_de_regra = Cadeia.ativa? && event.data[:performed_by].instance_of?(AutomationRule)
      yield
    ensure
      RegraDisparaRegra.vinda_de_regra = anterior
    end

    def performed_by_automation?(event)
      return false if Cadeia.ativa?

      super
    end

    def execute_rule(rule, account, conversation, message: nil)
      return if RegraDisparaRegra.vinda_de_regra && rule.execution_delay.present?

      super
    end
  end

  # Crm::StageAutomations::Runner: cada automação da etapa entra na cadeia. A lista vai no contexto, porque os passos
  # com atraso e a volta do Decisor rodam em job.
  module Etapa
    private

    def run_automation(automation, stage_id, trigger_event)
      return super unless Cadeia.vale_para?(@card.account)

      resultado = Cadeia.com("etapa:#{automation.id}", @card.account_id) do
        @automation_context = @automation_context.merge(CHAVE_NO_CONTEXTO => Cadeia.origens, CHAVE_DA_RAIZ => Cadeia.raiz)
        super
      end
      return resultado unless resultado.is_a?(Cadeia::Recusa)

      Cadeia.registrar_recusa(resultado, account_id: @card.account_id, alvo: "card:#{@card.id}",
                                         conversa: @card.primary_conversation, nome: automation.name)
      nil
    end
  end

  # Crm::StageAutomations::StepSequence e Crm::StageAutomationStepJob: retomam a cadeia guardada no contexto.
  module SequenciaDeEtapa
    def perform(...)
      contexto = @automation_context.to_h.with_indifferent_access
      Cadeia.retomar(Cadeia.origens | Array(contexto[CHAVE_NO_CONTEXTO]), @card.account,
                     Cadeia.raiz || contexto[CHAVE_DA_RAIZ]) { super }
    end
  end

  module PassoDeEtapa
    def perform(card_id:, automation_context: {}, **)
      contexto = automation_context.to_h.with_indifferent_access
      return super if contexto[CHAVE_NO_CONTEXTO].blank?

      Cadeia.retomar(Cadeia.origens | Array(contexto[CHAVE_NO_CONTEXTO]), Crm::Card.find_by(id: card_id)&.account,
                     Cadeia.raiz || contexto[CHAVE_DA_RAIZ]) { super }
    end
  end

  # Autonomia::Decisores::PerguntarJob: o passo do Decisor de uma regra sai para um job e, com a resposta, retoma a
  # regra do passo seguinte. A cadeia vai junto no job (inclusive nas novas tentativas), como o contexto vai no
  # PerguntarEtapaJob. A retomada depois de uma pessoa decidir a dúvida começa sem cadeia: a pausa humana a encerra.
  module PerguntaDaRegra
    CHAVE_NO_JOB = 'autonomia_cadeia'.freeze

    def serialize
      cadeia = Cadeia.ativa? ? { 'conta' => Cadeia.conta_id, 'origens' => Cadeia.origens, 'raiz' => Cadeia.raiz } : @autonomia_cadeia
      cadeia.present? ? super.merge(CHAVE_NO_JOB => cadeia) : super
    end

    def deserialize(job_data)
      super
      @autonomia_cadeia = job_data[CHAVE_NO_JOB]
    end

    def perform(...)
      cadeia = @autonomia_cadeia.to_h
      return super if cadeia.blank?

      Cadeia.retomar(cadeia['origens'], Account.find_by(id: cadeia['conta']), cadeia['raiz']) { super }
    end
  end
end
