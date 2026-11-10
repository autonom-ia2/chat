# O CONTADOR DO DIA de cada conta em cada fonte do catálogo (#2858, F0). Uma linha por conta, fonte e dia (no fuso da
# conta: a `Execucao` roda nele), atualizada por SQL atômico: dois turnos ao mesmo tempo nunca contam um só.
#
#   - `consultas`: as que passaram pelo limite diário (vindas do cache ou da fonte);
#   - `do_cache`, `pela_reserva`, `nao_encontradas`, `sem_resposta` (nenhuma fonte respondeu): o desfecho de cada uma;
#   - `recusadas`: as que nem chegaram à fonte (limite, corte, pedido inválido, sem acesso);
#   - `motivos`: quantas vezes cada motivo de falha apareceu no dia, inclusive a falha de cada fonte que a reserva
#     cobriu (`brasilapi.tempo_esgotado`). Os nomes vêm só de constantes do código, nunca de texto de fora.
#
# Isolamento: toda leitura passa por `da_conta` (a conta de quem pergunta). Nada aqui guarda o que foi consultado (CEP,
# CNPJ): só contagens.
class Autonomia::FerramentasProntas::Uso < ApplicationRecord
  self.table_name = 'autonomia_ferramentas_prontas_usos'

  DESFECHOS = %w[do_cache pela_reserva nao_encontradas sem_resposta recusadas].freeze

  belongs_to :account

  scope :da_conta, ->(account) { where(account_id: account.id) }

  class << self
    def hoje
      Time.zone.today
    end

    # Conta uma consulta, só se o dia ainda está abaixo do limite. -> true quando contou; false quando o limite já foi
    # atingido (nada muda). Uma instrução só: o INSERT do primeiro uso do dia ou o UPDATE condicional.
    # Fora do cache de consultas do ActiveRecord (`uncached`): ligado em todo job e request, ele devolveria o RETURNING da
    # primeira chamada às seguintes do mesmo job, sem executar o INSERT, e o limite deixaria de contar.
    def reservar!(account_id:, fonte:, limite:)
      return false if limite.to_i <= 0

      sql = <<~SQL.squish
        INSERT INTO #{table_name} (account_id, fonte, dia, consultas, created_at, updated_at)
        VALUES (:conta, :fonte, :dia, 1, NOW(), NOW())
        ON CONFLICT (account_id, fonte, dia) DO UPDATE
          SET consultas = #{table_name}.consultas + 1, updated_at = NOW()
          WHERE #{table_name}.consultas < :limite
        RETURNING consultas
      SQL
      comando = sanitize_sql_array([sql, { conta: account_id, fonte: fonte, dia: hoje, limite: limite.to_i }])
      contou = uncached { connection.select_value(comando) }.present?
      connection.clear_query_cache # a escrita não passou pelo caminho que suja o cache: leitura seguinte relê a linha
      contou
    end

    # Soma 1 no desfecho (`DESFECHOS`) e em cada motivo. Desfecho fora da lista é defeito nosso: levanta.
    def anotar!(account_id:, fonte:, desfecho: nil, motivos: [])
      raise ArgumentError, "desfecho desconhecido: #{desfecho}" if desfecho && DESFECHOS.exclude?(desfecho.to_s)

      contagem = Array(motivos).map(&:to_s).tally
      return if desfecho.nil? && contagem.empty?

      connection.exec_update(sanitize_sql_array([sql_de_anotar(desfecho), parametros_de_anotar(account_id, fonte, desfecho, contagem)]))
    end

    private

    def sql_de_anotar(desfecho)
      soma = desfecho ? ", #{desfecho} = #{table_name}.#{desfecho} + 1" : ''
      <<~SQL.squish
        INSERT INTO #{table_name} (account_id, fonte, dia, #{desfecho || 'recusadas'}, motivos, created_at, updated_at)
        VALUES (:conta, :fonte, :dia, :inicial, CAST(:motivos AS jsonb), NOW(), NOW())
        ON CONFLICT (account_id, fonte, dia) DO UPDATE
          SET motivos = (
            SELECT COALESCE(jsonb_object_agg(chave, total), '{}'::jsonb) FROM (
              SELECT chave, SUM(valor::int) AS total FROM (
                SELECT key AS chave, value AS valor FROM jsonb_each_text(#{table_name}.motivos)
                UNION ALL
                SELECT key, value FROM jsonb_each_text(CAST(:motivos AS jsonb))
              ) juntos GROUP BY chave
            ) somados
          ), updated_at = NOW()#{soma}
      SQL
    end

    def parametros_de_anotar(account_id, fonte, desfecho, contagem)
      { conta: account_id, fonte: fonte, dia: hoje, inicial: desfecho ? 1 : 0, motivos: contagem.to_json }
    end
  end
end
