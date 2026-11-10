# A campanha da vez (#2414 G55): uma linha por automação, vez e passo de campanha num gatilho recorrente de card ou
# contato. Quem mexe é Autonomia::Automacao::CampanhaDaOcorrencia, sempre sob a trava da vez. A vez fecha pelo estado
# das execuções dela; aqui ficam só os lotes da varredura, a campanha que saiu e quando fechou.
class Autonomia::Automacao::CampanhaDaVez < ApplicationRecord
  self.table_name = 'autonomia_automacao_campanhas_da_vez'

  belongs_to :account
  belongs_to :automacao, class_name: 'Autonomia::Automacao::Definicao'

  # Quanto a vez fechada fica guardada (LimparRegistrosJob), contado de quando fechou. É a trava contra mandar a mesma vez
  # de novo: prazo próprio, não o do registro.
  RETENCAO = 90.days

  validates :ocorrencia, :passo, presence: true

  # As vezes com alguma execução ainda aberta (a marca da execução começa pela da vez, EstadoDaVez).
  scope :com_execucao_aberta, lambda {
    where(<<~SQL.squish)
      EXISTS (SELECT 1 FROM autonomia_automacao_execucoes execucao
              WHERE execucao.account_id = autonomia_automacao_campanhas_da_vez.account_id
                AND execucao.automacao_id = autonomia_automacao_campanhas_da_vez.automacao_id
                AND starts_with(execucao.evento, autonomia_automacao_campanhas_da_vez.ocorrencia || ':')
                AND execucao.finalizada_em IS NULL)
    SQL
  }

  # A varredura já enfileirou todos os lotes e todos rodaram (o lote repetido conta uma vez só).
  def lotes_rodaram? = !lotes.nil? && lotes_feitos.uniq.size >= lotes

  # Os lotes enfileirados que não rodaram.
  def lotes_fora = [lotes.to_i - lotes_feitos.uniq.size, 0].max
end
