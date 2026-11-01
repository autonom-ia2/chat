# A sequência de automações que levou à ação de agora (D6 do ADR-001, #2414 F1).
#
# Uma automação muda a conversa ou o card, isso dispara outra, que dispara outra. A cadeia guarda quem já rodou
# nessa sequência ("regra:12", "etapa:4", "automacao:7") e recusa duas coisas: a mesma automação de novo (laço) e
# uma quarta automação diferente (cascata). É proteção contra defeito de montagem, não limite de uso.
#
# Vive FORA do `Current` de propósito. O `ActionService` das regras termina com `Current.reset`, o tratador de
# exceção dos controllers também zera o `Current`, e a `ChamadaInterna` do Guia roda um pedido inteiro no meio. A
# marca antiga (`performed_by` igual a uma regra) se perdia nesses pontos. A cadeia só muda dentro de um bloco
# (`com`/`restaurada`), e o bloco sempre devolve o valor anterior.
#
# Entre processos ela viaja como lista de strings: no evento despachado (CadeiaNoDespacho), no contexto dos jobs
# das automações de etapa e no job do Decisor das regras. Os três motores contam na mesma cadeia.
#
# Só existe com a flag `automacao_fundacao`, na entrada e na volta: quem retoma (`retomar`) confere a flag de novo.
# Desligar a flag é o rollback, e um job enfileirado antes volta a rodar sem a cadeia.
class Autonomia::Automacao::Cadeia
  PROFUNDIDADE_MAXIMA = 3

  Recusa = Struct.new(:origem, :motivo, :origens, keyword_init: true)

  thread_mattr_accessor :origens_atuais, :conta_atual_id, instance_accessor: false

  class << self
    def origens
      origens_atuais || []
    end

    def ativa?
      origens.any?
    end

    # A conta da cadeia em curso, para quem a leva adiante (evento, job) conferir a flag na volta.
    def conta_id
      conta_atual_id
    end

    # nil quando pode entrar; senão o motivo: :laco (já rodou nesta sequência) ou :profundidade.
    def motivo_para_recusar(origem)
      return :laco if origens.include?(origem)

      :profundidade if origens.size >= PROFUNDIDADE_MAXIMA
    end

    # Roda o bloco com `origem` na cadeia. Recusada, não roda e devolve uma Recusa (o chamador decide como registrar).
    def com(origem, conta_id = self.conta_id, &)
      motivo = motivo_para_recusar(origem)
      return Recusa.new(origem: origem, motivo: motivo, origens: origens) if motivo

      restaurada(origens + [origem], conta_id, &)
    end

    # Porta de entrada dos motores. Com a flag, entra na cadeia e pode recusar. Sem ela, só roda o bloco: nada vai
    # para o evento nem para o contexto dos jobs, e cada motor faz exatamente o de antes da F1 (F1.5).
    def entrar(origem, account, &)
      return com(origem, account.id, &) if vale_para?(account)

      yield
    end

    # Retoma a cadeia que veio de fora (evento, contexto, job), só se a conta ainda tem a flag. Desligada, roda o bloco
    # sem cadeia, como antes da F1.
    def retomar(lista, account, &)
      return yield if Array(lista).empty? || !vale_para?(account)

      restaurada(lista, account.id, &)
    end

    # Roda o bloco com esta cadeia e devolve a anterior no fim. Lista vazia ou nil = sem cadeia.
    def restaurada(lista, conta_id = nil)
      anterior = [origens_atuais, conta_atual_id]
      self.origens_atuais = Array(lista).map(&:to_s).freeze
      self.conta_atual_id = conta_id
      yield
    ensure
      self.origens_atuais, self.conta_atual_id = anterior
    end

    # A conta pediu a contagem comum? Sem a flag, cada motor segue com a proteção que tinha antes da F1.
    def vale_para?(account)
      Autonomia::Automacao.fundacao?(account)
    end

    # O motivo vai para o log. A cascata cortada vai também para o histórico da conversa, como atividade (só a equipe
    # vê): quem montou as automações entende por que a quarta não rodou. O laço fica só no log: uma regra que muda a
    # conversa e casaria de novo com a própria mudança é o caso comum, e uma nota a cada vez seria ruído.
    def registrar_recusa(recusa, account_id:, alvo:, conversa: nil, nome: nil)
      Rails.logger.info(
        "[automacao][cadeia] recusada origem=#{recusa.origem} motivo=#{recusa.motivo} " \
        "cadeia=#{recusa.origens.join('>')} conta=#{account_id} alvo=#{alvo}"
      )
      registrar_no_historico(conversa, nome) if conversa && recusa.motivo == :profundidade
    end

    private

    def registrar_no_historico(conversa, nome)
      conteudo = I18n.with_locale(conversa.account.locale) { I18n.t('conversations.activity.automacao.cadeia_profundidade', nome: nome) }
      ::Conversations::ActivityMessageJob.perform_later(
        conversa, account_id: conversa.account_id, inbox_id: conversa.inbox_id, message_type: :activity, content: conteudo
      )
    end
  end
end
