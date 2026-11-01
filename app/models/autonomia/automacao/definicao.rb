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
  validate :versao_ativa_desta_automacao

  # Desligar sempre funciona (D7, F3.4): quem está no meio para agora, e a próxima rodada de quem já estava na fila
  # também para (o executor confere `ativa`).
  def desligar!
    transaction do
      update!(ativa: false)
      execucoes.abertas.find_each { |execucao| execucao.update!(estado: 'parada', travada_em: nil) }
    end
  end

  # "Assumir e religar" (F3.7): a automação passa a agir como `usuario`, se ele pode. Nunca liga em nome de quem não
  # pode: devolve o motivo e não muda nada.
  def assumir_e_religar!(usuario)
    self.ligada_por = usuario
    motivo = ::Autonomia::Automacao::Acesso.new(self).motivo
    if motivo
      restore_attributes([:ligada_por_id])
      return motivo
    end

    update!(ativa: true)
    nil
  end

  def salvar_versao!(receita:, autor: nil)
    with_lock do
      versao = versoes.create!(account: account, numero: versoes.maximum(:numero).to_i + 1, receita: receita, autor: autor)
      update!(versao_ativa: versao)
      versao
    end
  end

  private

  def versao_ativa_desta_automacao
    errors.add(:versao_ativa, :invalid) if versao_ativa && (versao_ativa.automacao_id != id || versao_ativa.account_id != account_id)
  end
end
