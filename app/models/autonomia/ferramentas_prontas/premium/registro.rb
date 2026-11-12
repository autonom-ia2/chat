# A TELEMETRIA DE CADA CONSULTA PREMIUM (#2858, F7): uma linha por consulta à BigDataCorp, para gerar a cobrança na
# fatura (decisão do Rodrigo, 10/11). A F7 não cobra nada sozinha: só registra.
#
#   - `fonte` é o card; `consulta` e `dataset`, o que foi pedido (a BigDataCorp cobra por dataset);
#   - `resultado`: `encontrado`, `sem_registro` (a fonte respondeu e não havia registro; conta), `documento_invalido` (a
#     BigDataCorp recusou o documento; conta) ou `falha` (não conta);
#   - `cobranca`: `gratis` (dentro das 20 do card), `cobrada` (da 21ª em diante, pelo preço) ou `sem_cobranca` (cache,
#     falha, ou a 21ª do Experimente sem o clique no preço, motivo `sem_clique_no_preco`). `numero` é a posição da
#     consulta contada no card da conta (1, 2, ... 21);
#   - `custo`: o que a BigDataCorp cobra de nós (0 no cache e na falha); `preco`: o que vai à fatura (custo × 1,5, só na
#     cobrada);
#   - `id_na_fonte`: o `QueryId` da BigDataCorp, para conferir com o painel dela. Nunca o valor consultado;
#   - `tool_run_id`: a execução em segundo plano (`autonomia_agent_tool_runs`) que fez a consulta; nil no turno. Uma
#     linha por execução (índice único).
class Autonomia::FerramentasProntas::Premium::Registro < ApplicationRecord
  self.table_name = 'autonomia_ferramentas_premium_consultas'

  # `em_andamento`: a consulta do Experimente que ainda não terminou (`Cobranca.em_andamento!`); sem custo e sem contar.
  RESULTADOS = %w[encontrado sem_registro documento_invalido falha em_andamento].freeze
  COBRANCAS = %w[gratis cobrada sem_cobranca].freeze

  belongs_to :account

  validates :fonte, :consulta, :dataset, :dia, presence: true
  validates :resultado, inclusion: { in: RESULTADOS }
  validates :cobranca, inclusion: { in: COBRANCAS }

  scope :da_conta, ->(account) { where(account_id: account.id) }
end
