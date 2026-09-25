# Comparação da nota legada com a do Orth nas buscas de uma conta (#681), para a tabela de quem sobe e quem desce que o
# Rodrigo aprova antes da virada. Só lê: cada busca nova guarda as duas notas em lead_scoring (Scoring::SearchScoring).
#
# Sobe, desce e mesma faixa são contados pela faixa do card (Scoring::Band), não pela prioridade: a prioridade é um
# percentil dentro da busca e muda para quase todo lead, e o que a conta vê mudar é a faixa. A matriz dá, para cada faixa
# legada, em que faixa do Orth o lead cai. A diferença de prioridade só ordena as maiores mudanças. Cada lead de cada
# busca conta uma vez; a busca servida do cache repete a de origem e fica de fora. Busca com leads e sem a nota do Orth
# (anterior ao modo sombra, ou com a nota fora do ar) é contada à parte e não entra na comparação.
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
      leads: rows.size, sobem: rows.count { |row| row[:band_shift].positive? }, descem: rows.count { |row| row[:band_shift].negative? },
      mesma_faixa: rows.count { |row| row[:band_shift].zero? }, matriz: matrix(rows), top10: top(rows)
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
      row(lead_id, legacy, orth)
    end
  end

  # Prioridade ausente conta como zero, como já contava na diferença de prioridade.
  def row(lead_id, legacy, orth)
    legacy_priority = legacy['priority_score'].to_f
    orth_priority = orth['priority_score'].to_f
    legacy_band = Band.code(legacy_priority)
    orth_band = Band.code(orth_priority)

    { lead_id: lead_id.to_i, legacy: legacy, orth: orth, delta: orth_priority - legacy_priority,
      legacy_band: legacy_band, orth_band: orth_band, band_shift: Band.rank(orth_band) - Band.rank(legacy_band) }
  end

  # No motor legado o que a conta vê é o topo e a sombra está em 'orth'; virada a conta, a legada está em 'legacy'.
  def legacy_and_orth(scoring)
    orth = scoring['orth']
    return if orth.blank?

    [scoring['legacy'].presence || scoring, orth]
  end

  # Faixa legada (origem) para faixa do Orth (destino), as quatro do card nas duas pontas, zeradas quando não há lead.
  def matrix(rows)
    Band::CODES.index_with do |from|
      Band::CODES.index_with { |to| rows.count { |row| row[:legacy_band] == from && row[:orth_band] == to } }
    end
  end

  def top(rows)
    chosen = rows.sort_by { |row| [-row[:delta].abs, row[:lead_id]] }.first(TOP)
    names = Autonomia::Prospecting::Lead.where(account: @account, id: chosen.pluck(:lead_id)).pluck(:id, :name).to_h
    chosen.map { |row| top_row(row, names[row[:lead_id]]) }
  end

  def top_row(row, name)
    { lead_id: row[:lead_id], nome: name, legacy: row[:legacy]['priority_score'].to_f.round, orth: row[:orth]['priority_score'].to_f.round,
      faixa_legacy: Band.label(row[:legacy_band]), faixa_orth: Band.label(row[:orth_band]), motivo: row[:orth]['human_insight'] }
  end
end
