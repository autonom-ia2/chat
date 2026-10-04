# == Schema Information
#
# Table name: autonomia_guide_executions
#
#  id                 :bigint           not null, primary key
#  desfeita_em        :datetime
#  expira_em          :datetime         not null
#  jobs               :jsonb            not null
#  passos             :jsonb            not null
#  pendencias         :jsonb            not null
#  relatorio_desfazer :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  desfeita_por_id    :bigint
#  task_id            :bigint
#  user_id            :bigint           not null
#
# Indexes
#
#  idx_autonomia_guide_executions_dono                  (account_id,user_id,created_at)
#  index_autonomia_guide_executions_on_account_id       (account_id)
#  index_autonomia_guide_executions_on_desfeita_por_id  (desfeita_por_id)
#  index_autonomia_guide_executions_on_expira_em        (expira_em)
#  index_autonomia_guide_executions_on_task_id          (task_id)
#  index_autonomia_guide_executions_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (desfeita_por_id => users.id) ON DELETE => nullify
#  fk_rails_...  (task_id => autonomia_guide_tasks.id) ON DELETE => nullify
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
  # #936 — cada lote de uma tarefa longa é uma execução.
  belongs_to :tarefa, class_name: 'Autonomia::Guide::Tarefa', foreign_key: :task_id, optional: true, inverse_of: :execucoes
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

  # #936 — os jobs que o passo deixou na fila, de toda classe: a pausa de segurança de uma
  # tarefa longa mostra quantos ("25 automações, 0 webhooks").
  def anotar_jobs(contagem)
    return if contagem.blank?

    update!(jobs: jobs.merge(contagem) { |_classe, antes, agora| antes + agora })
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

  # A lista "Feito pelo Guia": cada turno numa linha, e os lotes de uma tarefa longa (#936) juntos
  # numa linha só, com os totais da tarefa, no lugar do lote mais recente dela.
  def self.resumos(lista)
    vistas = Set.new
    lista.filter_map do |execucao|
      next execucao.resumo if execucao.task_id.nil?
      next unless vistas.add?(execucao.task_id)

      execucao.tarefa&.resumo_feito
    end
  end

  # O que a tela mostra embaixo da resposta e na lista "Feito pelo Guia".
  def resumo
    { 'id' => id, 'passos' => passos.map { |passo| passo.slice('acao', 'frase', 'ok', 'registro') },
      'pendencias' => pendencias, 'desfazivel' => desfazivel?,
      'desfeita_em' => desfeita_em&.iso8601, 'expira_em' => expira_em.iso8601,
      'criada_em' => created_at.iso8601, 'relatorio' => relatorio_desfazer.presence }
  end
end
