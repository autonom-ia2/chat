# Onde ficam as renovações de uma conta (E5, #2898): o funil e a etapa em que o card de renovação nasce, quantos dias
# antes do fim da vigência e se as mensagens ao cliente saem. Uma linha por conta (índice único no banco). Funil e etapa
# nulos querem dizer "a conta ainda não escolheu" ou "o funil escolhido foi apagado" (a chave anula): nos dois casos nada
# vira card até alguém escolher.
#
# O banco só confere que o funil, a etapa e a pessoa existem, não de quem são: a validação daqui recusa o funil de
# outra conta, a etapa de outro funil e a pessoa que não é da conta. `user` é quem escolheu por último.
class Carteira::RenovacaoConfig < ApplicationRecord
  self.table_name = 'carteira_renovacao_configs'

  DIAS_PADRAO = 60
  # Do primeiro dia até dez anos: acima disso é erro de digitação, e número grande demais nem cabe na coluna.
  DIAS = (1..3650)
  MENSAGENS = %w[mandar nao_mandar].freeze

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline', optional: true
  belongs_to :stage, class_name: 'Crm::PipelineStage', optional: true
  belongs_to :user, optional: true
  # O aviso da carteira no sino tem esta linha como ator: sem ela, o aviso não tem o que abrir.
  has_many :notifications, as: :primary_actor, dependent: :delete_all

  validates :account_id, uniqueness: true
  validates :dias_antes, numericality: { only_integer: true, in: DIAS }
  validates :mensagens, inclusion: { in: MENSAGENS }
  validate :funil_e_etapa_da_conta, if: -> { will_save_change_to_pipeline_id? || will_save_change_to_stage_id? }
  validate :pessoa_da_conta, if: :will_save_change_to_user_id?

  # O aviso da carteira no sino (Notification `carteira_renovacao`) tem esta linha como ator: só o id, sem dado de cliente.
  def push_event_data
    { id: id }
  end

  # A conta já disse onde ficam as renovações (e o funil escolhido continua existindo).
  def escolhida?
    pipeline_id.present? && stage_id.present?
  end

  private

  def funil_e_etapa_da_conta
    errors.add(:pipeline, :invalid) if pipeline && pipeline.account_id != account_id
    errors.add(:stage, :invalid) if stage && stage.pipeline_id != pipeline_id
  end

  def pessoa_da_conta
    errors.add(:user, :invalid) if user && !AccountUser.exists?(account_id: account_id, user_id: user.id)
  end
end
