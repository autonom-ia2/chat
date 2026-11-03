require 'rails_helper'

RSpec.describe Autonomia::Automacao::Gatilhos do
  it 'tem os mesmos tipos que o esquema da receita: acrescentar um sem o outro quebra o salvar ou o motor' do
    no_esquema = Autonomia::Automacao::Receita::ESQUEMA.dig('properties', 'gatilho', 'properties', 'tipo', 'enum')

    expect(described_class.tipos).to match_array(no_esquema)
  end

  it 'diz em que alvo cada gatilho roda, só entre os que o motor conhece' do
    expect(described_class::LISTA.values.map(&:alvo).uniq - Autonomia::Automacao::Contexto::TIPOS).to be_empty
    expect(described_class.alvo('conversa.criada')).to eq('Conversation')
    expect(described_class.alvo('nao.existe')).to be_nil
  end

  it 'marca o evento do despacho em microssegundos e em UTC: reabrir e resolver no mesmo segundo são dois fatos' do
    conversa = instance_double(Conversation, id: 7)
    instante = Time.zone.parse('2026-11-03 10:00:00.123456 -03:00')

    expect(described_class.marca_do_despacho('conversa.aberta', conversa, instante)).to eq('conversa.aberta:7:2026-11-03T13:00:00.123456Z')
    expect(described_class.marca_do_despacho('conversa.aberta', conversa, Time.zone.parse('2026-11-03 10:00:00.123457 -03:00')))
      .not_to eq(described_class.marca_do_despacho('conversa.aberta', conversa, instante))
  end
end
