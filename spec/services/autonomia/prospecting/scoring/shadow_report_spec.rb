require 'rails_helper'

# Comparação da nota legada com a do Orth nas buscas de uma conta (#681): base da tabela de quem sobe e quem desce que o
# Rodrigo aprova antes de virar a conta. Só leitura.
RSpec.describe Autonomia::Prospecting::Scoring::ShadowReport do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }

  def lead(name)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "places/#{name}", name: name)
  end

  def entry(legacy:, orth:, engine: 'legacy')
    legacy_values = { 'score' => legacy - 3, 'priority_score' => legacy, 'band' => Autonomia::Prospecting::Scoring::Band.code(legacy),
                      'human_insight' => 'frase legada' }
    orth_values = { 'score' => orth - 5, 'priority_score' => orth, 'band' => Autonomia::Prospecting::Scoring::Band.code(orth),
                    'human_insight' => "Orth #{orth}" }
    return legacy_values.except('band', 'human_insight').merge('orth' => orth_values) if engine == 'legacy'

    orth_values.except('band', 'human_insight').merge('legacy' => legacy_values, 'orth' => orth_values)
  end

  def search(lead_scoring, status: :completed, created_at: Time.current, **metadata)
    Autonomia::Prospecting::Search.create!(account: account, user: user, query: 'padaria', provider: 'mock', status: status,
                                           created_at: created_at, metadata: { 'lead_scoring' => lead_scoring }.merge(metadata))
  end

  it 'conta quem sobe, desce e fica igual pela prioridade, nas buscas do período, e ordena as maiores mudanças' do
    alfa = lead('Alfa')
    beta = lead('Beta')
    gama = lead('Gama')
    search({ alfa.id.to_s => entry(legacy: 10, orth: 90), beta.id.to_s => entry(legacy: 80, orth: 60) })
    search({ gama.id.to_s => entry(legacy: 50, orth: 50, engine: 'orth'), beta.id.to_s => entry(legacy: 40, orth: 45, engine: 'orth') })
    search({ alfa.id.to_s => entry(legacy: 0, orth: 100) }, created_at: 10.days.ago)
    search({ alfa.id.to_s => entry(legacy: 0, orth: 100) }, status: :cached)

    report = described_class.new(account: account, since: 7.days.ago).perform

    expect(report.except(:top10)).to eq(buscas: 2, buscas_sem_sombra: 0, leads: 4, sobem: 2, descem: 1, iguais: 1)
    expect(report[:top10].first).to eq(
      lead_id: alfa.id, nome: 'Alfa', legacy: 10, orth: 90, faixa_legacy: 'Prioridade baixa', faixa_orth: 'Lead muito quente',
      motivo: 'Orth 90'
    )
    expect(report[:top10].pluck(:nome)).to eq(%w[Alfa Beta Beta Gama])
  end

  it 'conta a busca sem nota sombra à parte e não a compara' do
    search({ lead('Alfa').id.to_s => { 'score' => 10.0, 'priority_score' => 10.0 } }, 'score_shadow_error' => 'RuntimeError')

    report = described_class.new(account: account, since: 1.day.ago).perform

    expect(report).to eq(buscas: 1, buscas_sem_sombra: 1, leads: 0, sobem: 0, descem: 0, iguais: 0, top10: [])
  end

  it 'não olha buscas de outra conta' do
    other = create(:account)
    Autonomia::Prospecting::Search.create!(account: other, user: create(:user, account: other), query: 'x', provider: 'mock',
                                           status: :completed, metadata: { 'lead_scoring' => { '1' => entry(legacy: 1, orth: 99) } })

    expect(described_class.new(account: account, since: 1.day.ago).perform[:buscas]).to eq(0)
  end

  it 'não grava nada' do
    search({ lead('Alfa').id.to_s => entry(legacy: 10, orth: 90) })

    expect { described_class.new(account: account, since: 1.day.ago).perform }
      .not_to(change { [Autonomia::Prospecting::Search.maximum(:updated_at), Autonomia::Prospecting::Lead.maximum(:updated_at)] })
  end

  it 'mostra no máximo dez mudanças' do
    scoring = Array.new(12) { |index| [lead("L#{index}").id.to_s, entry(legacy: index, orth: 90)] }.to_h
    search(scoring)

    expect(described_class.new(account: account, since: 1.day.ago).perform[:top10].size).to eq(10)
  end
end
