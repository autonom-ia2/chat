# Comparação da nota legada com a do Orth nas buscas de uma conta (#681), para a tabela de quem sobe e quem desce que o
# Rodrigo aprova antes da virada. Só lê: cada busca nova guarda as duas notas em lead_scoring (Scoring::SearchScoring).
#
# Compara a prioridade (0 a 100), que é o que decide a fila "Ligar 1º" e a faixa do card. Cada lead de cada busca conta
# uma vez; a busca servida do cache repete a de origem e fica de fora. Busca com leads e sem a nota do Orth (anterior ao
# modo sombra, ou com a nota fora do ar) é contada à parte e não entra na comparação.
class Autonomia::Prospecting::Scoring::ShadowReport
  TOP = 10
  Band = Autonomia::Prospecting::Scoring::Band

  def initialize(account:, since:)
    @account = account
    @since = since
  end

  def perform
    per_search = searches.map { |search| [search, rows_for(search)] }
    rows = per_search.flat_map(&:last)

    {
      buscas: per_search.size, buscas_sem_sombra: per_search.count { |search, search_rows| without_shadow?(search, search_rows) },
      leads: rows.size, sobem: rows.count { |row| row[:delta].positive? }, descem: rows.count { |row| row[:delta].negative? },
      iguais: rows.count { |row| row[:delta].zero? }, top10: top(rows)
    }
  end

  private

  def searches
    Autonomia::Prospecting::Search.completed.where(account: @account, created_at: @since..).order(:created_at)
  end

  def without_shadow?(search, search_rows)
    search_rows.empty? && search.metadata.to_h['lead_scoring'].present?
  end

  def rows_for(search)
    search.metadata.to_h['lead_scoring'].to_h.filter_map do |lead_id, scoring|
      pair = legacy_and_orth(scoring.to_h)
      next if pair.nil?

      legacy, orth = pair
      { lead_id: lead_id.to_i, legacy: legacy, orth: orth, delta: orth['priority_score'].to_f - legacy['priority_score'].to_f }
    end
  end

  # No motor legado o que a conta vê é o topo e a sombra está em 'orth'; virada a conta, a legada está em 'legacy'.
  def legacy_and_orth(scoring)
    orth = scoring['orth']
    return if orth.blank?

    [scoring['legacy'].presence || scoring, orth]
  end

  def top(rows)
    chosen = rows.sort_by { |row| [-row[:delta].abs, row[:lead_id]] }.first(TOP)
    names = Autonomia::Prospecting::Lead.where(account: @account, id: chosen.pluck(:lead_id)).pluck(:id, :name).to_h
    chosen.map { |row| top_row(row, names[row[:lead_id]]) }
  end

  def top_row(row, name)
    legacy_priority = row[:legacy]['priority_score']
    orth_priority = row[:orth]['priority_score']
    { lead_id: row[:lead_id], nome: name, legacy: legacy_priority.to_f.round, orth: orth_priority.to_f.round,
      faixa_legacy: Band.label(Band.code(legacy_priority)), faixa_orth: Band.label(Band.code(orth_priority)),
      motivo: row[:orth]['human_insight'] }
  end
end
