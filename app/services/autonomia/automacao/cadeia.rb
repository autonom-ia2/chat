# A sequência de automações que levou à ação de agora (D6 do ADR-001, #2414 F1).
#
# Uma automação muda a conversa ou o card, isso dispara outra, que dispara outra. A cadeia guarda quem já rodou
# nessa sequência ("regra:12", "etapa:4", "automacao:7") e recusa três coisas: a mesma automação de novo no mesmo
# ramo (laço; auto-disparo quando ela casa com a própria mudança), uma quarta automação diferente (cascata) e a mesma
# automação de novo na mesma raiz (repetida). É
# proteção contra defeito de montagem, não limite de uso.
#
# A raiz é a mudança que começou tudo: um id novo no primeiro `com`, que segue com a cadeia. Uma regra com duas
# ações gera dois eventos, e a regra seguinte casaria com os dois; pela raiz ela roda uma vez só. A marca fica no
# Redis (SET NX, com validade), porque os ramos da mesma raiz rodam em jobs diferentes.
#
# Vive FORA do `Current` de propósito. O `ActionService` das regras termina com `Current.reset`, o tratador de
# exceção dos controllers também zera o `Current`, e a `ChamadaInterna` do Guia roda um pedido inteiro no meio. A
# marca antiga (`performed_by` igual a uma regra) se perdia nesses pontos. A cadeia só muda dentro de um bloco
# (`com`/`restaurada`), e o bloco sempre devolve o valor anterior.
#
# Entre processos ela viaja como lista de strings, com a raiz ao lado: no evento despachado (CadeiaNoDespacho), no contexto dos jobs
# das automações de etapa e no job do Decisor das regras. Os três motores contam na mesma cadeia.
#
# Só existe com a flag `automacao_fundacao`, na entrada e na volta: quem retoma (`retomar`) confere a flag de novo.
# Desligar a flag é o rollback, e um job enfileirado antes volta a rodar sem a cadeia.
class Autonomia::Automacao::Cadeia
  PROFUNDIDADE_MAXIMA = 3
  # Quanto tempo a marca "já rodou nesta raiz" dura. Passos com atraso maiores que isto seguem protegidos pelo laço
  # e pela profundidade; só a marca da raiz expira.
  VALIDADE_DA_RAIZ = 1.day

  Recusa = Struct.new(:origem, :motivo, :origens, :raiz, keyword_init: true)

  thread_mattr_accessor :origens_atuais, :conta_atual_id, :raiz_atual, instance_accessor: false

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

    def raiz
      raiz_atual
    end

    # #2428: a Automação livre que está agindo agora, quando o passo "ação" move o card pela porta da frente (pela
    # ChamadaInterna, como quem ligou): `{ origem: 'livre', id: }`, para o Crm::Cards::Mover marcar o movimento como
    # dela. Vem da cadeia, e não do `Current`, pelo mesmo motivo da cadeia: o pedido de dentro mexe no `Current`.
    # nil fora de cadeia, ou quando quem age por último é uma regra ou uma automação de etapa.
    def automacao_livre
      tipo, id = origens.last.to_s.split(':', 2)
      { origem: 'livre', id: id.to_i } if tipo == 'automacao' && id.present?
    end

    # nil quando pode entrar; senão o motivo: :auto_disparo (a automação de agora casou com a própria mudança), :laco
    # (já rodou antes neste ramo) ou :profundidade.
    def motivo_para_recusar(origem)
      return :auto_disparo if origens.last == origem
      return :laco if origens.include?(origem)

      :profundidade if origens.size >= PROFUNDIDADE_MAXIMA
    end

    # Roda o bloco com `origem` na cadeia. Recusada, não roda e devolve uma Recusa (o chamador decide como registrar).
    # Fora de uma cadeia, abre uma raiz nova.
    def com(origem, conta_id = self.conta_id, &)
      raiz = self.raiz || SecureRandom.uuid
      motivo = motivo_para_recusar(origem) || (:repetida unless primeira_vez?(raiz, origem))
      return Recusa.new(origem: origem, motivo: motivo, origens: origens, raiz: raiz) if motivo

      restaurada(origens + [origem], conta_id, raiz, &)
    end

    # Porta de entrada dos motores. Com a flag, entra na cadeia e pode recusar. Sem ela, só roda o bloco: nada vai
    # para o evento nem para o contexto dos jobs, e cada motor faz exatamente o de antes da F1 (F1.5).
    def entrar(origem, account, &)
      return com(origem, account.id, &) if vale_para?(account)

      yield
    end

    # Retoma a cadeia que veio de fora (evento, contexto, job), só se a conta ainda tem a flag. Desligada, roda o bloco
    # sem cadeia, como antes da F1.
    def retomar(lista, account, raiz = nil, &)
      return yield if Array(lista).empty? || !vale_para?(account)

      restaurada(lista, account.id, raiz, &)
    end

    # Roda o bloco com esta cadeia e devolve a anterior no fim. Lista vazia ou nil = sem cadeia.
    def restaurada(lista, conta_id = nil, raiz = nil)
      anterior = [origens_atuais, conta_atual_id, raiz_atual]
      self.origens_atuais = Array(lista).map(&:to_s).freeze
      self.conta_atual_id = conta_id
      self.raiz_atual = raiz
      yield
    ensure
      self.origens_atuais, self.conta_atual_id, self.raiz_atual = anterior
    end

    # A conta pediu a contagem comum? Sem a flag, cada motor segue com a proteção que tinha antes da F1.
    def vale_para?(account)
      Autonomia::Automacao.fundacao?(account)
    end

    # O motivo vai para o log. Na conversa fica uma nota só por raiz, como atividade (só a equipe vê): quem montou as
    # automações entende por que uma delas não rodou. O auto-disparo (a regra que casa de novo com a própria mudança) é
    # o caso comum e fica só no log; o laço entre automações diferentes, a cascata e a repetida vão para a nota.
    def registrar_recusa(recusa, account_id:, alvo:, conversa: nil, nome: nil)
      Rails.logger.info(
        "[automacao][cadeia] recusada origem=#{recusa.origem} motivo=#{recusa.motivo} " \
        "cadeia=#{recusa.origens.join('>')} raiz=#{recusa.raiz} conta=#{account_id} alvo=#{alvo}"
      )
      return if conversa.nil? || recusa.motivo == :auto_disparo

      registrar_no_historico(conversa, nome) if primeira_vez?(recusa.raiz, "nota:#{conversa.id}")
    end

    private

    # Marca atômica: só o primeiro a marcar esta raiz com esta chave recebe true.
    def primeira_vez?(raiz, chave)
      Redis::Alfred.set("automacao:raiz:#{raiz}:#{chave}", 1, nx: true, ex: VALIDADE_DA_RAIZ).present?
    end

    def registrar_no_historico(conversa, nome)
      conteudo = I18n.with_locale(conversa.account.locale) { I18n.t('conversations.activity.automacao.cadeia_parada', nome: nome) }
      ::Conversations::ActivityMessageJob.perform_later(
        conversa, account_id: conversa.account_id, inbox_id: conversa.inbox_id, message_type: :activity, content: conteudo
      )
    end
  end
end
