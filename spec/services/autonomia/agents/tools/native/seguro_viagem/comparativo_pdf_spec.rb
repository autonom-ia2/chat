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
                        { 'id_beneficio' => 2595, 'nome' => 'Perda de Bagagem', 'descricao_completa' => '',
                          'valor' => 'R$ 1.500', 'moeda' => 'BRL' }] }]
  end
  # Meio-dia em UTC: o dia é o mesmo em qualquer fuso do Brasil.
  let(:cotacao) do
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: agente, id_cotacao: 'c-1',
                                               pedido: pedido, planos: planos, created_at: Time.utc(2026, 11, 25, 15))
  end
  let(:bytes) { described_class.new(cotacao: cotacao, nome_corretora: 'Corretora Exemplo').render }
  let(:leitor) { PDF::Reader.new(StringIO.new(bytes)) }
  # Espaço normalizado: o PDF quebra texto longo em linhas, e o leitor devolve a quebra.
  let(:texto) { leitor.pages.map(&:text).join("\n").split.join(' ') }

  it 'devolve um PDF de capa, comparação e "antes de contratar"' do
    expect(bytes).to start_with('%PDF-')
    expect(leitor.page_count).to eq(3)
    expect(texto).to include('Seguro Viagem', 'Compare as opções', 'Antes de contratar')
  end

  it 'a corretora aparece como quem envia' do
    expect(texto).to include('Cotação preparada por Corretora Exemplo')
  end

  it 'traz os planos, os preços e as coberturas principais' do
    expect(texto).to include('Especial UA 100K BRL', 'Especial UA 30K BRL', 'R$ 360,00', 'R$ 210,00', 'R$ 100.000',
                             'R$ 30.000 em despesas médicas', 'Perda de bagagem R$ 1.500')
  end

  it 'o país vai por extenso no selo da capa' do
    pedido['destinos_nomes'] = ['Portugal']
    expect(texto).to include('Portugal · 3 viajantes')
    expect(texto).not_to include('BR · 3 viajantes')
  end

  it 'cotação antiga, sem o nome do país, mostra a sigla' do
    expect(texto).to include('BR · 3 viajantes')
  end

  it 'mais de um país: lista por extenso' do
    pedido['destinos_nomes'] = %w[Portugal Espanha França]
    expect(texto).to include('Portugal, Espanha e França · 3 viajantes')
  end

  it 'o preço por pessoa vem rotulado pela idade, na ordem das idades' do
    expect(texto).to include('47 anos: R$ 120,00', '19 anos: R$ 120,00', '12 anos: R$ 120,00')
    expect(texto.index('47 anos: R$ 120,00')).to be < texto.index('19 anos: R$ 120,00')
    expect(texto.index('19 anos: R$ 120,00')).to be < texto.index('12 anos: R$ 120,00')
  end

  it 'cobertura que o plano não tem sai com traço' do
    expect(texto).to include('Cancelamento de viagem —')
  end

  it 'os rótulos seguem a regra: mais despesas médicas por real é a recomendada, o mais barato é o econômico' do
    expect(texto).to include('OPÇÃO MAIS RECOMENDADA PARA ESTA VIAGEM', 'MAIS RECOMENDADA', 'MAIS ECONÔMICA')
    expect(texto).not_to include('MAIOR COBERTURA')
  end

  it 'um plano só: "opção disponível"' do
    planos.pop
    expect(texto).to include('OPÇÃO DISPONÍVEL')
    expect(texto).not_to include('MAIS RECOMENDADA', 'MAIS ECONÔMICA')
  end

  it 'a cotação vale até o fim do dia em que foi feita' do
    expect(texto).to include('25/11/2026', '25/11/2026, 23h59')
  end

  it '"Ver coberturas" é link para as condições gerais oficiais' do
    anotacoes = leitor.pages.flat_map { |pagina| Array(pagina.attributes[:Annots]).map { |item| leitor.objects.deref(item) } }
    enderecos = anotacoes.map { |anotacao| leitor.objects.deref(anotacao[:A])[:URI] }
    expect(texto).to include('Ver coberturas')
    expect(enderecos.size).to eq(3) # um por plano e o da última folha
    expect(enderecos.uniq).to eq([described_class::CondicoesGerais.url])
  end

  it 'a seguradora e o processo SUSEP no rodapé dos cartões' do
    expect(texto).to include('Seguradora: Zurich Minas Brasil Seguros S.A · Processo SUSEP 15414.644662/2023-04')
  end

  it 'não traz comissão, id de produto nem o código interno do plano' do
    expect(texto).not_to include('comissao', '99,9', '5382451', 'P1', 'P2')
  end
end
