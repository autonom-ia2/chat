# QUANTAS CONSULTAS PREMIUM CADA CONTA JÁ USOU EM CADA CARD (#2858, F7): a base das 20 grátis por card e por conta. Um
# card não mexe no contador do outro. Só a consulta que conta (encontrada ou sem registro, fora do cache) soma aqui.
class Autonomia::FerramentasProntas::Premium::Saldo < ApplicationRecord
  self.table_name = 'autonomia_ferramentas_premium_saldos'

  belongs_to :account

  scope :da_conta, ->(account) { where(account_id: account.id) }

  # Soma 1 e devolve a posição desta consulta no card (1 = a primeira). Uma instrução só: dois turnos ao mesmo tempo
  # nunca recebem a mesma posição. Fora do cache de consultas do ActiveRecord, como o `Uso.reservar!`.
  def self.contar!(account_id:, fonte:)
    sql = <<~SQL.squish
      INSERT INTO #{table_name} (account_id, fonte, contadas, created_at, updated_at)
      VALUES (:conta, :fonte, 1, NOW(), NOW())
      ON CONFLICT (account_id, fonte) DO UPDATE SET contadas = #{table_name}.contadas + 1, updated_at = NOW()
      RETURNING contadas
    SQL
    posicao = uncached { connection.select_value(sanitize_sql_array([sql, { conta: account_id, fonte: fonte }])) }
    connection.clear_query_cache
    posicao.to_i
  end

  # -> { 'fonte' => contadas } da conta.
  def self.da_conta_por_fonte(account)
    da_conta(account).pluck(:fonte, :contadas).to_h
  end
end
