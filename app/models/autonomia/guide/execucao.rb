# == Schema Information
#
# Table name: autonomia_guide_executions
#
#  id                 :bigint           not null, primary key
#  desfeita_em        :datetime
#  expira_em          :datetime         not null
#  passos             :jsonb            not null
#  pendencias         :jsonb            not null
#  relatorio_desfazer :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  desfeita_por_id    :bigint
#  user_id            :bigint           not null
#
# Indexes
#
#  idx_autonomia_guide_executions_dono                  (account_id,user_id,created_at)
#  index_autonomia_guide_executions_on_account_id       (account_id)
#  index_autonomia_guide_executions_on_desfeita_por_id  (desfeita_por_id)
#  index_autonomia_guide_executions_on_expira_em        (expira_em)
#  index_autonomia_guide_executions_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (desfeita_por_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#

# Um turno em que o Guia mexeu na conta, com o que dá para desfazer (#855).
#
# O Guia age sem pedir confirmação — o que protege é poder voltar. Cada passo
# executado fica aqui, com as linhas do banco que ele criou, alterou ou apagou
# (`Mudanca`). Por 5 dias, quem pediu desfaz o turno inteiro com um clique.
#
# `pendencias` diz, com honestidade, o que NÃO volta: a plataforma escreveu
# numa tabela sem passar pelo Rails (update_all, delete_all, SQL direto), e
# essa escrita não tem o "antes" guardado.
class Autonomia::Guide::Execucao < ApplicationRecord
  self.table_name = 'autonomia_guide_executions'

  PRAZO = 5.days

  belongs_to :account
  belongs_to :user
  belongs_to :desfeita_por, class_name: 'User', optional: true
  has_many :mudancas, -> { order(:ordem) }, class_name: 'Autonomia::Guide::Mudanca',
                                            foreign_key: :execution_id, inverse_of: :execucao,
                                            dependent: :delete_all

  scope :vigentes, -> { where('expira_em > ?', Time.current) }
  scope :de, ->(account, user) { where(account: account, user: user) }

  before_validation { self.expira_em ||= PRAZO.from_now }

  def self.abrir(account:, user:)
    create!(account: account, user: user)
  end

  def registrar_passo(acao:, frase:, feito:, registro: nil)
    self.passos = passos + [{ 'acao' => acao.to_s, 'frase' => frase.to_s, 'ok' => feito, 'registro' => registro }]
    save!
    passos.size - 1
  end

  def anotar_pendencias(tabelas)
    novas = Array(tabelas) - pendencias
    update!(pendencias: pendencias + novas) if novas.any?
  end

  def desfeita?
    desfeita_em.present?
  end

  def vencida?
    expira_em <= Time.current
  end

  def desfazivel?
    !desfeita? && !vencida? && mudancas.exists?
  end

  # O que a tela mostra embaixo da resposta e na lista "Feito pelo Guia".
  def resumo
    { 'id' => id, 'passos' => passos.map { |passo| passo.slice('acao', 'frase', 'ok', 'registro') },
      'pendencias' => pendencias, 'desfazivel' => desfazivel?,
      'desfeita_em' => desfeita_em&.iso8601, 'expira_em' => expira_em.iso8601,
      'criada_em' => created_at.iso8601, 'relatorio' => relatorio_desfazer.presence }
  end
end
