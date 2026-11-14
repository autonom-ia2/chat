# Onde ficam as renovações de uma conta (E5, #2898): o funil e a etapa em que o card de renovação nasce, quantos dias
# antes do fim da vigência e se as mensagens ao cliente saem. Uma linha por conta (índice único no banco).
#
# Só vira card quando a escolha vale (`escolhida?`): funil e etapa guardados, e o funil ativo. O funil arquivado continua
# guardado (arquivar só muda o status dele), mas não recebe card. O funil ou a etapa apagados somem daqui sem passar
# pelo app (a chave anula a coluna): `escolha` diz qual é o caso, para a tela avisar.
#
# O banco só confere que o funil, a etapa e a pessoa existem, não de quem são: a validação daqui recusa o funil de
# outra conta, a etapa de outro funil e a pessoa que não é da conta. `user` é quem escolheu o funil por último: só muda
# junto com o funil, e sai quando alguém tira a escolha (Carteira::Renovacao::SalvarAjustes). É por ele que se sabe que
# a escolha sumiu: sobrou quem escolheu, sem o funil.
class Carteira::RenovacaoConfig < ApplicationRecord
  self.table_name = 'carteira_renovacao_configs'

  DIAS_PADRAO = 60
  # Do primeiro dia até dez anos: acima disso é erro de digitação, e número grande demais nem cabe na coluna.
  DIAS = (1..3650)
  MENSAGENS = %w[mandar nao_mandar].freeze
  # Como está a escolha do funil (`escolha`).
  FEITA = 'feita'.freeze
  NUNCA_FEITA = 'nunca_feita'.freeze
  FUNIL_ARQUIVADO = 'funil_arquivado'.freeze
  SUMIU = 'sumiu'.freeze

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

  # A conta disse onde ficam as renovações, e o funil escolhido continua existindo e ativo.
  def escolhida?
    escolha == FEITA
  end

  # Como está a escolha do funil:
  # - `feita`: funil e etapa guardados, funil ativo;
  # - `funil_arquivado`: o funil escolhido foi arquivado (restaurado, volta a valer sozinho);
  # - `sumiu`: o funil ou a etapa escolhidos foram apagados. Sobrou a metade da escolha (o funil sem a etapa) ou quem
  #   escolheu sem o funil;
  # - `nunca_feita`: ninguém escolheu, ou quem escolheu tirou a escolha.
  def escolha
    return pipeline&.active? ? FEITA : FUNIL_ARQUIVADO if pipeline_id && stage_id

    [pipeline_id, stage_id, user_id].any? ? SUMIU : NUNCA_FEITA
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
