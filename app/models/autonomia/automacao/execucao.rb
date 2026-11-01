# Uma automação rodando para um alvo: conversa, card ou contato (#2414, F2 #2452). Fica na versão em que entrou.
#
# Só pode haver uma aberta por automação, alvo e gatilho: o índice único do banco vale enquanto `finalizada_em` é nula.
# Por isso `finalizada_em` sai daqui, a cada gravação, a partir do estado: nula num estado terminal travaria aquele
# alvo para sempre. Quem grava sem callback (`update_columns`, `update_all`) tem de preencher as duas juntas.
class Autonomia::Automacao::Execucao < ApplicationRecord
  self.table_name = 'autonomia_automacao_execucoes'

  ABERTAS = %w[andando esperando].freeze
  TERMINAIS = %w[concluida falhou interrompida parada].freeze
  ESTADOS = (ABERTAS + TERMINAIS).freeze

  belongs_to :account
  belongs_to :automacao, class_name: 'Autonomia::Automacao::Definicao', inverse_of: :execucoes
  belongs_to :versao, class_name: 'Autonomia::Automacao::Versao'
  belongs_to :alvo, polymorphic: true
  has_many :registros, class_name: 'Autonomia::Automacao::Registro', inverse_of: :execucao, dependent: nil

  validates :estado, inclusion: { in: ESTADOS }
  validates :chave_gatilho, presence: true
  validate :da_mesma_automacao

  before_save :marcar_finalizada

  scope :abertas, -> { where(finalizada_em: nil) }

  private

  # Versão e automação de outra conta prenderiam a exclusão daquela conta nesta chave estrangeira.
  def da_mesma_automacao
    errors.add(:versao, :invalid) if versao && versao.automacao_id != automacao_id
    errors.add(:automacao, :invalid) if automacao && automacao.account_id != account_id
  end

  def marcar_finalizada
    self.finalizada_em = TERMINAIS.include?(estado) ? (finalizada_em || Time.current) : nil
  end
end
