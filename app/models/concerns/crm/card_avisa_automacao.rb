# Lote 4 da Automação livre (#2682): o card mudou num campo que a receita lê (Autonomia::Automacao::Valores, `card.*`), e
# o "esperar até" que espera nele confere a condição agora, em vez de no fim do prazo: o campo que o corretor preencheu,
# a etapa nova, o ganho. Depois do commit; a Escuta (`card_mudou`) loga o erro e nunca desfaz a edição. É o ponto único
# da Automação livre para "o card mudou": pega qualquer escrita com callback, venha da tela, da API, da IA ou do lote.
module Crm::CardAvisaAutomacao
  extend ActiveSupport::Concern

  # As colunas por trás dos valores `card.*` (título, etapa, funil, situação, valor, responsável, time, motivo da perda
  # e os atributos). Mudança só de outra coluna (updated_at, contadores) não acorda ninguém.
  LIDAS_PELA_AUTOMACAO = %w[title stage_id pipeline_id status value_cents owner_id team_id lost_reason custom_attributes].freeze

  included do
    after_update :dono_anterior_na_transacao, if: :saved_change_to_owner_id?
    after_rollback { @dono_anterior_na_transacao = nil }
    after_update_commit :avisar_automacao_livre, if: -> { saved_changes.keys.intersect?(LIDAS_PELA_AUTOMACAO) || @dono_anterior_na_transacao }
  end

  private

  # A troca de responsável (G9, #2707) é também um gatilho: vai com o responsável anterior. Guardado dentro da
  # transação, no primeiro save que troca: no commit, `saved_changes` é só o do último save.
  def dono_anterior_na_transacao
    @dono_anterior_na_transacao ||= [saved_changes['owner_id'].first]
  end

  def avisar_automacao_livre
    anterior = @dono_anterior_na_transacao&.first
    trocou = @dono_anterior_na_transacao && anterior != owner_id
    @dono_anterior_na_transacao = nil
    ::Autonomia::Automacao::Escuta.card_mudou(self)
    ::Autonomia::Automacao::Escuta.responsavel_mudou(self, anterior) if trocou
  end
end
