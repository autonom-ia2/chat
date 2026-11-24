require 'rails_helper'

# A conferência de números do Guia (#3158), portada do `Captain::Copilot::NumberCheck`. Os casos do Copilot
# continuam valendo, e os do português também: data 23/11, vírgula decimal, número colado em letra.
RSpec.describe Autonomia::Guide::NumerosSemFonte do
  let(:resultados) { [{ total: 1899, matched: 28, active_misses: 11, groups: [{ group: 'Pranav', value: 52.27 }] }.to_json, '{"seconds":7380}'] }

  it 'aceita o número que a ferramenta mostra, arredonda, soma, subtrai, divide ou converte de segundos' do
    rascunho = 'We found 1,899 conversations. 28 missed the SLA and 11 more are still open, 39 in all, 17 apart. That is 1.47% of them. ' \
               'Pranav averaged 52.3 hours, and the longest wait was 2.05 hours.'

    expect(described_class.new(resultados).sem_fonte(rascunho)).to eq([])
  end

  it 'aceita variação percentual e a conta que a resposta mostra' do
    conferencia = described_class.new([{ four_stars: 12, five_stars: 18, rated: 76, last_week: 202, this_week: 64 }.to_json])

    expect(conferencia.sem_fonte('Resolutions fell from 202 to 64, down 68.3%. 30 of 76 ratings were 4 or 5 stars, 39.47% of them.')).to eq([])
  end

  it 'não confere pergunta de volta à pessoa', :aggregate_failures do
    expect(described_class.new(resultados).sem_fonte('Listo as 4.321 ou as 9.876?')).to eq([])
    expect(described_class.new(resultados).sem_fonte('Vou listar as 4.321.')).to eq([{ numero: '4.321', frase: 'Vou listar as 4.321.' }])
  end

  it 'lê os formatos de número de outros idiomas, e aponta o errado', :aggregate_failures do
    conferencia = described_class.new([{ total: 1899, contacts: 123_456, share: 63.35 }.to_json])

    expect(conferencia.sem_fonte("Foram 1.899 conversas. Il y en a eu 1 899. São 63,35 %. Es waren 1'899. We have 1,23,456 contacts."))
      .to eq([])
    expect(described_class.new([{ total: 1899 }.to_json]).sem_fonte('Foram 1.900 conversas.').pluck(:numero)).to eq(['1.900'])
  end

  it 'não combina ids e datas de uma tabela, para eles não sustentarem um percentual inventado', :aggregate_failures do
    linhas = (1201..1300).map { |id| "| [##{id}](/app/accounts/7/conversations/#{id}) | open | 2026-09-#{format('%02d', (id % 28) + 1)} |" }
    textos = [{ content: linhas.join("\n") }.to_json, { total: 340, refunds: 5 }.to_json]

    expect(described_class.new(textos).sem_fonte('5 das 340 foram reembolso, 1,47% delas.')).to eq([])
    expect(described_class.new(textos).sem_fonte('5 das 340 foram reembolso, 6,8% delas.').pluck(:numero)).to eq(['6,8'])
  end

  it 'deixa de fora datas, horas, links, referências e marcadores de lista' do
    rascunho = "1. Em 2023-09-04T10:00:00Z às 10:30, [#4321](/app/accounts/7/conversations/4321) reabriu.\n2) Veja #5678. De 01/10 a 31/10."

    expect(described_class.new(resultados).sem_fonte(rascunho)).to eq([])
  end

  it 'não lê número colado em letra' do
    expect(described_class.new(resultados).sem_fonte('Às 14h30 eram 5x mais.')).to eq([])
  end

  it 'em JSON, vírgula separa números, não agrupa milhar' do
    expect(described_class.new(['[100,200]']).sem_fonte('Foram 100 e 200, 300 ao todo.')).to eq([])
  end

  it 'aponta o número que nenhum resultado sustenta, como a média de duas médias, com a frase' do
    conferencia = described_class.new([{ groups: [{ group: 'Email', value: 10 }, { group: 'Chat', value: 20 }] }.to_json])

    expect(conferencia.sem_fonte('O e-mail leva 10 horas e o chat 20. Na média são 15 horas.'))
      .to eq([{ numero: '15', frase: 'Na média são 15 horas.' }])
  end

  it 'nunca derruba a resposta: falha vira lista vazia' do
    allow(described_class).to receive(:new).and_raise(StandardError)

    expect(described_class.registrar(texto: 'Foram 3.', conhecidos: [], registro: nil, account_id: 1)).to eq([])
  end
end
