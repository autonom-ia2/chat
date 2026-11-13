# Onde ficam as renovações de uma conta (E5, #2898): o funil e a etapa em que o card de renovação nasce, quantos dias
# antes do fim da vigência e se as mensagens ao cliente saem. Uma linha por conta (índice único no banco). Funil e etapa
# nulos querem dizer "a conta ainda não escolheu" ou "o funil escolhido foi apagado" (a chave anula): nos dois casos nada
# vira card até alguém escolher.
#
# O banco só confere que o funil e a etapa existem, não de quem são: a validação daqui recusa o funil de outra conta e a
# etapa de outro funil. `user` é quem escolheu por último.
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

  validates :account_id, uniqueness: true
  validates :dias_antes, numericality: { only_integer: true, in: DIAS }
  validates :mensagens, inclusion: { in: MENSAGENS }
  validate :funil_e_etapa_da_conta, if: -> { will_save_change_to_pipeline_id? || will_save_change_to_stage_id? }

  # A conta já disse onde ficam as renovações (e o funil escolhido continua existindo).
  def escolhida?
    pipeline_id.present? && stage_id.present?
  end

  private

  def funil_e_etapa_da_conta
    errors.add(:pipeline, :invalid) if pipeline && pipeline.account_id != account_id
    errors.add(:stage, :invalid) if stage && stage.pipeline_id != pipeline_id
  end
end
