require 'rails_helper'

# O FORMULÁRIO DO ESPECIALISTA NASCE DO ADAPTER — entrega 2 do Agente de Cotação, termos 1 e 2.
#
# O que se prova: todo campo que o adapter declara (menos os dois que não se expõem ao modelo)
# aparece no formulário, e nada aparece no formulário que o adapter não declare. É a guarda que
# faz o formulário não envelhecer em silêncio quando o adapter ganha um campo.
#
# PROVA POR MUTAÇÃO (10/09/2026): tirar o filtro de `NAO_EXPOSTOS` reprova "comissão e seguradoras
# não se expõem"; trocar o tipo `numero` por `string` reprova "os tipos são os do adapter"; deixar
# uma folha sem `required: false` reprova "toda folha é anulável".
RSpec.describe Autonomia::Insurance::Parametros do
  let(:schema) { Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO }
  let(:grupos) { described_class.de_auto(schema) }
  let(:folhas) { grupos.flat_map { |g| g['properties'].map { |p| "#{g['name']}.#{p['name']}" } } }

  it 'declara todo campo do adapter, menos os dois que o modelo não escreve, e nada além deles' do
    do_adapter = schema['campos'].map { |c| c['campo'] } - described_class::NAO_EXPOSTOS

    expect(folhas).to match_array(do_adapter)
    expect(folhas.size).to be > 80
  end

  it 'comissão e seguradoras a consultar não se expõem: uma é da corretora, a outra é decisão do PO' do
    expect(described_class::NAO_EXPOSTOS).to match_array(%w[commissionPercent insurerCodes])
    expect(folhas).not_to include('commissionPercent', 'insurerCodes')
    expect(grupos.map { |g| g['name'] }).not_to include('commissionPercent', 'insurerCodes')
  end

  it 'os tipos são os do adapter, traduzidos para o JSON Schema, e toda folha é anulável' do
    por_caminho = grupos.flat_map { |g| g['properties'].map { |p| ["#{g['name']}.#{p['name']}", p] } }.to_h

    expect(por_caminho['vehicle.plate']['type']).to eq('string')
    expect(por_caminho['vehicle.annualMileage']['type']).to eq('number')
    expect(por_caminho['vehicle.youngDriver']['type']).to eq('boolean')
    expect(por_caminho.values).to all(include('required' => false))
    expect(por_caminho.values.map { |p| p['description'] }).to all(be_present)
  end

  it 'cada grupo tem o rótulo escrito aqui; grupo novo do adapter entra com rótulo genérico, nunca some' do
    expect(grupos.find { |g| g['name'] == 'vehicle' }['description']).to eq(described_class::GRUPOS['vehicle'])

    com_grupo_novo = { 'campos' => schema['campos'] + [{ 'campo' => 'novo.campo', 'tipo' => 'texto', 'descricao' => 'x' }] }
    novo = described_class.de_auto(com_grupo_novo).find { |g| g['name'] == 'novo' }

    expect(novo).to be_present
    expect(novo['description']).to eq('Campos de novo.')
    expect(novo['properties'].map { |p| p['name'] }).to eq(['campo'])
  end

  it 'a descrição de cada campo é a do adapter, com os valores aceitos' do
    rastreador = grupos.find { |g| g['name'] == 'vehicle' }['properties'].find { |p| p['name'] == 'trackerCode' }

    expect(rastreador['description']).to include('Valores:', 'Ituran')
  end

  it 'sem schema, não há grupo nenhum' do
    expect(described_class.de_auto(nil)).to eq([])
  end
end
