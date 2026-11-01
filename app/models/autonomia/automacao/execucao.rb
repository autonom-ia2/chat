# Uma automação rodando para um alvo: conversa, card ou contato (#2414, F2 #2452). Fica na versão em que entrou.
#
# Só pode haver uma aberta por automação, alvo e gatilho: o índice único do banco vale enquanto `finalizada_em` é nula.
# Por isso `finalizada_em` sai daqui, a cada gravação, a partir do estado: nula num estado terminal travaria aquele
# alvo para sempre. Quem grava sem callback (`update_columns`, `update_all`) tem de preencher as duas juntas; o CHECK
# do banco recusa o par desencontrado. A lista de TERMINAIS é a mesma do CHECK da migration.
class Autonomia::Automacao::Execucao < ApplicationRecord
  self.table_name = 'autonomia_automacao_execucoes'

  ABERTAS = %w[andando esperando].freeze
  TERMINAIS = %w[concluida falhou interrompida parada].freeze
  ESTADOS = (ABERTAS + TERMINAIS).freeze
  # Quanto tempo a execução finalizada fica, depois que os registros dela já saíram (30 dias): 90 dias cabe um "não
  # repetir por N dias" e a pergunta "esse cliente já passou por aqui?" sem guardar o histórico passo a passo
  # (#2459, decisão da Automação em 01/11).
  RETENCAO = 90.days

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

  # Versão e automação de outra conta prenderiam a exclusão daquela conta nesta chave estrangeira; alvo de outra conta
  # faria o motor agir fora da conta.
  def da_mesma_automacao
    errors.add(:versao, :invalid) if versao && versao.automacao_id != automacao_id
    errors.add(:automacao, :invalid) if automacao && automacao.account_id != account_id
    errors.add(:alvo, :invalid) if alvo && alvo.account_id != account_id
  end

  def marcar_finalizada
    self.finalizada_em = TERMINAIS.include?(estado) ? (finalizada_em || Time.current) : nil
  end
end
