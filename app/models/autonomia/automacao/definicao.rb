# Uma automação da conta (#2414, F2 #2452). Nasce desligada (`ativa` false no banco). A receita mora nas versões:
# `salvar_versao!` cria a próxima e passa a ativa para ela; as anteriores nunca mudam.
#
# `ligada_por` é quem ligou: o motor (F3) age como essa pessoa (D1). Sem ela (usuário apagado), a automação não roda
# e pausa; nunca troca para outro usuário.
class Autonomia::Automacao::Definicao < ApplicationRecord
  self.table_name = 'autonomia_automacoes'

  ORIGENS = %w[guia manual receita conversao].freeze

  belongs_to :account
  belongs_to :ligada_por, class_name: 'User', optional: true
  belongs_to :versao_ativa, class_name: 'Autonomia::Automacao::Versao', optional: true
  has_many :versoes, class_name: 'Autonomia::Automacao::Versao', foreign_key: :automacao_id, inverse_of: :automacao,
                     dependent: nil
  has_many :execucoes, class_name: 'Autonomia::Automacao::Execucao', foreign_key: :automacao_id, inverse_of: :automacao,
                       dependent: nil

  validates :nome, presence: true
  validates :origem, inclusion: { in: ORIGENS }

  def salvar_versao!(receita:, autor: nil)
    with_lock do
      versao = versoes.create!(account: account, numero: versoes.maximum(:numero).to_i + 1, receita: receita, autor: autor)
      update!(versao_ativa: versao)
      versao
    end
  end
end
