# A campanha da vez (#2414 G55): uma linha por automação, vez e passo de campanha num gatilho recorrente de card ou
# contato. Quem mexe é Autonomia::Automacao::CampanhaDaOcorrencia, sempre sob a trava da vez. A vez fecha pelo estado
# das execuções dela; aqui ficam só os lotes da varredura, a campanha que saiu e quando fechou.
class Autonomia::Automacao::CampanhaDaVez < ApplicationRecord
  self.table_name = 'autonomia_automacao_campanhas_da_vez'

  belongs_to :account
  belongs_to :automacao, class_name: 'Autonomia::Automacao::Definicao'

  validates :ocorrencia, :passo, presence: true

  # A varredura já enfileirou todos os lotes e todos rodaram (o lote repetido conta uma vez só).
  def lotes_rodaram? = !lotes.nil? && lotes_feitos.uniq.size >= lotes

  # Os lotes enfileirados que não rodaram.
  def lotes_fora = [lotes.to_i - lotes_feitos.uniq.size, 0].max
end
