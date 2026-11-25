require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account, inbox: create(:inbox, account: account)) }
  let(:agente) { Autonomia::Agents::Agent.create!(account: account, name: 'Contratado', agent_type: 'custom') }
  let(:pedido) do
    { 'destinos' => ['BR'], 'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06', 'idades' => [47, 19, 12],
      'motivo' => nil, 'universal' => {} }
  end
  let(:dmh) { { 'id_beneficio' => 2898, 'nome' => 'Despesas Médicas e Hospitalares (por evento)', 'descricao_completa' => '', 'moeda' => 'BRL' } }
  let(:planos) do
    [{ 'codigo' => 'P1', 'id_produto' => 5_382_451, 'nome' => 'Especial UA 100K BRL', 'preco_total' => '360.0',
       'max_parcelas' => 12, 'idade_minima' => 0, 'idade_maxima' => 65, 'comissao' => '99.9',
       'faixas' => [{ 'de' => 0, 'ate' => 65, 'valor' => '120.0', 'valor_moeda' => '120.0' }],
       'coberturas' => [dmh.merge('valor' => 'R$ 100.000')] },
     { 'codigo' => 'P2', 'id_produto' => 5_382_452, 'nome' => 'Especial UA 30K BRL', 'preco_total' => '210.0',
       'max_parcelas' => 6, 'idade_minima' => 0, 'idade_maxima' => 65,
       'faixas' => [{ 'de' => 0, 'ate' => 65, 'valor' => '70.0', 'valor_moeda' => '70.0' }],
       'coberturas' => [dmh.merge('valor' => 'R$ 30.000'),
                        { 'id_beneficio' => 2595, 'nome' => 'Extravio de Bagagem', 'descricao_completa' => '',
                          'valor' => 'R$ 1.500', 'moeda' => 'BRL' }] }]
  end
  let(:cotacao) do
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: agente, id_cotacao: 'c-1',
                                               pedido: pedido, planos: planos)
  end
  let(:bytes) { described_class.new(cotacao: cotacao, nome_corretora: 'Corretora Exemplo').render }
  # Espaço normalizado: o PDF quebra rótulo longo em linhas, e o leitor devolve a quebra.
  let(:texto) { PDF::Reader.new(StringIO.new(bytes)).pages.map(&:text).join("\n").split.join(' ') }

  it 'devolve um PDF' do
    expect(bytes).to start_with('%PDF-')
  end

  it 'traz a corretora, os planos, os preços e as coberturas' do
    expect(texto).to include('Corretora Exemplo', 'Especial UA 100K BRL', 'Especial UA 30K BRL', 'R$ 360,00', 'R$ 120,00',
                             'Despesas Médicas e Hospitalares (por evento)', 'Extravio de Bagagem')
  end

  it 'o país vai por extenso' do
    pedido['destinos_nomes'] = ['Portugal']
    expect(texto).to include('Destino: Portugal')
    expect(texto).not_to include('Destino: BR')
  end

  it 'cotação antiga, sem o nome do país, mostra a sigla' do
    expect(texto).to include('Destino: BR')
  end

  it 'mais de um país: rótulo no plural' do
    pedido['destinos_nomes'] = %w[Portugal Espanha]
    expect(texto).to include('Destinos: Portugal, Espanha')
  end

  it 'o preço por pessoa vem rotulado pela idade, na ordem das idades' do
    expect(texto).to include('47 anos: R$ 120,00', '19 anos: R$ 120,00', '12 anos: R$ 120,00')
    expect(texto.index('47 anos: R$ 120,00')).to be < texto.index('19 anos: R$ 120,00')
    expect(texto.index('19 anos: R$ 120,00')).to be < texto.index('12 anos: R$ 120,00')
  end

  it 'cobertura que o plano não tem sai com traço' do
    expect(texto).to include('—')
  end

  it 'não traz comissão, id de produto nem o código interno do plano' do
    expect(texto).not_to include('comissao', '5382451', 'P1')
  end
end
