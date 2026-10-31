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
# Entre processos ela viaja como lista de strings: no evento despachado (CadeiaNoDespacho) e no contexto dos jobs
# das automações de etapa. Os três motores contam na mesma cadeia.
class Autonomia::Automacao::Cadeia
  PROFUNDIDADE_MAXIMA = 3

  Recusa = Struct.new(:origem, :motivo, :origens, keyword_init: true)

  thread_mattr_accessor :origens_atuais, instance_accessor: false

  class << self
    def origens
      origens_atuais || []
    end

    def ativa?
      origens.any?
    end

    # nil quando pode entrar; senão o motivo: :laco (já rodou nesta sequência) ou :profundidade.
    def motivo_para_recusar(origem)
      return :laco if origens.include?(origem)

      :profundidade if origens.size >= PROFUNDIDADE_MAXIMA
    end

    # Roda o bloco com `origem` na cadeia. Recusada, não roda e devolve uma Recusa (o chamador decide como registrar).
    def com(origem, &)
      motivo = motivo_para_recusar(origem)
      return Recusa.new(origem: origem, motivo: motivo, origens: origens) if motivo

      restaurada(origens + [origem], &)
    end

    # Porta de entrada dos motores. Com a flag, pode recusar. Sem ela, só anota quem rodou, e o comportamento de
    # cada motor fica o de antes da F1 (F1.5).
    def entrar(origem, account, &)
      return com(origem, &) if vale_para?(account)

      restaurada(origens | [origem], &)
    end

    # Roda o bloco com a cadeia que veio de fora (evento, job). Lista vazia ou nil = sem cadeia.
    def restaurada(lista)
      anterior = origens_atuais
      self.origens_atuais = Array(lista).map(&:to_s).freeze
      yield
    ensure
      self.origens_atuais = anterior
    end

    # A conta pediu a contagem comum? Sem a flag, cada motor segue com a proteção que tinha antes da F1.
    def vale_para?(account)
      Autonomia::Automacao.fundacao?(account)
    end

    def registrar_recusa(recusa, account_id:, alvo:)
      Rails.logger.info(
        "[automacao][cadeia] recusada origem=#{recusa.origem} motivo=#{recusa.motivo} " \
        "cadeia=#{recusa.origens.join('>')} conta=#{account_id} alvo=#{alvo}"
      )
    end
  end
end
