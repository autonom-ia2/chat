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
  # Na ordem da Universal o mais caro vem primeiro: o PDF reordena pelo preço.
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
  let(:texto) { normalizar(leitor.pages.map(&:text).join("\n")) }
  let(:chamada) { 'Para contratar, responda na conversa com o nome do plano. Exemplo: “Quero o Especial UA 100K BRL”.' }

  # Espaço normalizado: o PDF quebra texto longo em linhas, e o leitor devolve a quebra; o espaço depois de "R$" é o que
  # não quebra linha.
  def normalizar(texto) = texto.tr(Prawn::Text::NBSP, ' ').split.join(' ')

  it 'com 2 planos cabe em 2 folhas: capa, e a comparação com "antes de contratar" embaixo' do
    expect(bytes).to start_with('%PDF-')
    expect(leitor.page_count).to eq(2)
    expect(normalizar(leitor.pages[1].text)).to include('Compare as opções', 'Antes de contratar')
  end

  it 'a corretora aparece como quem envia' do
    expect(texto).to include('Cotação preparada por Corretora Exemplo')
  end

  it 'traz os planos, os preços, o valor para médico e hospital e as coberturas principais' do
    expect(texto).to include('Especial UA 100K BRL', 'Especial UA 30K BRL', 'R$ 360,00', 'R$ 210,00',
                             'R$ 100.000 para médico e hospital', 'R$ 30.000 para médico e hospital',
                             'Bagagem perdida R$ 1.500')
  end

  it 'os cartões vão do mais barato ao mais caro' do
    comparacao = normalizar(leitor.pages[1].text)
    expect(comparacao.index('Especial UA 30K BRL')).to be < comparacao.index('Especial UA 100K BRL')
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

  it 'as idades do mesmo preço vão juntas numa linha' do
    expect(texto).to include('47, 19 e 12 anos: R$ 120,00 cada', '47, 19 e 12 anos: R$ 70,00 cada')
    expect(texto).not_to include('47 anos: R$ 120,00')
  end

  it 'se a soma por pessoa não fecha com o total, mostra só o total' do
    planos[0]['faixas'] = [{ 'de' => 0, 'ate' => 65, 'valor' => '100.0' }]
    expect(texto).not_to include('R$ 100,00 cada')
    expect(texto).to include('R$ 360,00', '47, 19 e 12 anos: R$ 70,00 cada')
  end

  it 'cobertura fora da lista do plano: "Não inclui"' do
    expect(texto).to include('Cancelamento Não inclui')
    expect(texto).not_to include('—')
  end

  it 'plano sem a lista de coberturas: "Não informado", nunca "Não inclui"' do
    planos[1]['coberturas'] = []
    expect(texto).to include('Bagagem perdida Não informado', 'Médico e hospital: não informado')
  end

  it 'os rótulos seguem a regra, sem caixa alta: mais despesas médicas por real é a recomendada, o mais barato é o econômico' do
    expect(texto).to include('Opção mais recomendada para esta viagem', 'Mais recomendada', 'Mais econômica')
    expect(texto).not_to include('Maior cobertura', 'MAIS RECOMENDADA', 'MAIS ECONÔMICA')
  end

  it 'o porquê da recomendada sai só dos números da cotação' do
    expect(texto).to include('Por R$ 150,00 a mais que a opção mais barata, a proteção para médico e hospital sobe de ' \
                             'R$ 30.000 para R$ 100.000.')
  end

  it 'a chamada para contratar vem na capa e na última parte, com o nome da recomendada' do
    expect(texto.scan(chamada).size).to eq(2)
    expect(texto).not_to include('Nas próximas páginas')
  end

  it 'um plano só: "opção disponível"' do
    planos.pop
    expect(texto).to include('Opção disponível', 'R$ 100.000 para médico e hospital por R$ 360,00 no total.')
    expect(texto).not_to include('Mais recomendada', 'Mais econômica')
  end

  it 'o preço vale até o fim do dia em que a cotação foi feita' do
    expect(texto).to include('Preço vale até', 'hoje, 25/11, 23h59',
                             'O preço vale para hoje, 25/11/2026. Se contratar depois, ele pode mudar.')
  end

  it 'um link só, na última parte, para as regras completas oficiais' do
    anotacoes = leitor.pages.flat_map { |pagina| Array(pagina.attributes[:Annots]).map { |item| leitor.objects.deref(item) } }
    enderecos = anotacoes.map { |anotacao| leitor.objects.deref(anotacao[:A])[:URI] }
    expect(texto).to include('Ler as regras completas do seguro')
    expect(texto).not_to include('Ver coberturas')
    expect(enderecos).to eq([described_class::CondicoesGerais.url])
  end

  it 'a seguradora e a SUSEP, em palavras de leigo, só na última parte' do
    expect(texto).to include('Seguradora: Zurich Minas Brasil Seguros S.A',
                             'Registro na SUSEP (órgão do governo que fiscaliza seguros): 15414.644662/2023-04')
    expect(texto.scan('SUSEP').size).to eq(1)
  end

  it 'não traz comissão, id de produto nem o código interno do plano' do
    expect(texto).not_to include('comissao', '99,9', '5382451', 'P1', 'P2')
  end
end
