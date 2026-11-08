require 'rails_helper'

# Contrato v2 do painel de desempenho (#2226): a fixture é inventada (uma loja genérica), nunca dado de cliente.
RSpec.describe Autonomia::Desempenho::Exportacao::Contrato do
  let(:painel) { JSON.parse(Rails.root.join('spec/fixtures/files/desempenho/contrato.json').read) }
  let(:agregados) { painel.except('versao', 'catalogo', 'procuras') }
  let(:semana) do
    agregados.deep_dup.tap do |dados|
      dados['meta']['periodo'] = dados['meta']['periodo'].merge('chave' => '7', 'inicio' => '2026-10-20', 'fim' => '2026-10-26')
    end
  end
  let(:pacote) do
    { 'versao' => 2, 'pacote' => true, 'catalogo' => painel['catalogo'], 'procuras' => painel['procuras'],
      'periodos' => { '30' => agregados, '7' => semana } }
  end

  it 'aceita a fixture e devolve o mesmo painel' do
    expect(described_class.validar!(painel)).to eq(painel)
  end

  it 'recusa outra versão com erro claro' do
    expect { described_class.validar!(painel.merge('versao' => 1)) }
      .to raise_error(described_class::Invalido, 'versao 2 esperada, veio 1')
  end

  it 'diz qual parte faltou, sem mostrar o conteúdo' do
    expect { described_class.validar!(painel.except('kpis').merge('meta' => painel['meta'].except('nomes'))) }
      .to raise_error(described_class::Invalido, 'faltou: kpis, meta.nomes')
  end

  it 'monta o painel do período com as procuras cujo dia cai entre o início e o fim, inclusive' do
    resultado = described_class.do_pacote(pacote, '7')
    dias = resultado['procuras'].map { |procura| procura['inicio'].first(10) }

    esperadas = painel['procuras'].count { |procura| procura['inicio'].first(10).between?('2026-10-20', '2026-10-26') }
    expect(resultado['procuras'].size).to eq(esperadas)
    expect(esperadas).to be_between(1, painel['procuras'].size - 1)
    expect(dias).to all(be_between('2026-10-20', '2026-10-26'))
    expect(dias).to include('2026-10-20', '2026-10-26')
    expect(resultado['catalogo']).to eq(painel['catalogo'])
    expect(resultado['versao']).to eq(2)
  end

  it 'mantém todas as procuras do período inteiro e recusa período que o pacote não tem' do
    expect(described_class.do_pacote(pacote, '30')['procuras'].size).to eq(painel['procuras'].size)
    expect { described_class.do_pacote(pacote, '90') }.to raise_error(described_class::Invalido, 'faltou: periodos.90')
    expect { described_class.do_pacote(pacote, 'ontem') }.to raise_error(described_class::Invalido, 'periodo desconhecido: ontem')
  end
end
