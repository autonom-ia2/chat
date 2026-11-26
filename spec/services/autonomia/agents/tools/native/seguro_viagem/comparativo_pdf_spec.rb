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

  # Espaço normalizado: o PDF quebra texto longo em linhas, e o leitor devolve a quebra; o espaço depois de "R$" é o que
  # não quebra linha.
  def normalizar(texto) = texto.tr(Prawn::Text::NBSP, ' ').split.join(' ')

  it 'com 2 planos cabe em 2 folhas: capa, e a comparação com "antes de contratar" embaixo' do
    expect(bytes).to start_with('%PDF-')
    expect(leitor.page_count).to eq(2)
    expect(normalizar(leitor.pages[1].text)).to include('Compare as opções', 'Antes de contratar')
  end

  it 'com 4 planos, "Antes de contratar" vai ao lado do último cartão: 2 folhas' do
    planos.push(planos[0].merge('nome' => 'Especial UA 60K BRL', 'preco_total' => '285.0',
                                'faixas' => [{ 'de' => 0, 'ate' => 65, 'valor' => '95.0' }],
                                'coberturas' => [dmh.merge('valor' => 'R$ 60.000')]),
                planos[0].merge('nome' => 'Especial UA 250K BRL', 'preco_total' => '540.0',
                                'faixas' => [{ 'de' => 0, 'ate' => 65, 'valor' => '180.0' }],
                                'coberturas' => [dmh.merge('valor' => 'R$ 250.000')]))
    expect(leitor.page_count).to eq(2)
    expect(normalizar(leitor.pages[1].text)).to include('Especial UA 250K BRL', 'Antes de contratar')
  end

  it 'corretora de nome muito longo: o nome encurta com "…" no rodapé e a marca fica inteira' do
    longo = 'Corretora Exemplo de Seguros, Previdência Privada e Planos de Saúde do Brasil Ltda'
    pdf = PDF::Reader.new(StringIO.new(described_class.new(cotacao: cotacao, nome_corretora: longo).render))
    # Pelos trechos de texto (`runs`): o `text` da página aperta a linha longa contra o número da página.
    rodapes = pdf.pages.map { |pagina| normalizar(pagina.runs.map(&:text).join("\n")) }
    expect(rodapes).to all(include('Cotação preparada por Corretora Exemplo', '… · Planos Universal Assistance'))
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

  it 'só informa: sem chamada para responder (o próximo passo é da conversa com o agente)' do
    expect(texto).not_to include('Para contratar', 'responda na conversa', 'Próximo passo', 'Nas próximas páginas')
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

  describe 'planos anuais e destino internacional (#3223)' do
    # O anual mais barato e com a maior cobertura: se entrasse na comparação, seria a econômica e a de maior cobertura.
    # Nome curto: no cartão de 3 colunas o nome longo quebra, e o leitor mistura as linhas dos cartões lado a lado.
    def anual(nome, preco)
      { 'codigo' => 'P9', 'nome' => nome, 'preco_total' => preco, 'max_parcelas' => 12, 'idade_minima' => 0,
        'idade_maxima' => 65, 'multiviagem' => true, 'dias_por_viagem' => 30,
        'faixas' => [{ 'de' => 0, 'ate' => 65, 'valor' => (BigDecimal(preco) / 3).to_s('F') }],
        'coberturas' => [dmh.merge('id_beneficio' => 2899, 'valor' => '$300.000')] }
    end

    let(:comparacao) { normalizar(leitor.pages.drop(1).map(&:text).join("\n")) }

    it 'os anuais vão depois dos de viagem única, numa seção com a linha de leigo' do
      planos.push(anual('Anual UA 150', '150.0'), anual('Anual UA 300', '600.0'))
      expect(comparacao).to include('Se você viaja mais vezes no ano',
                                    'Planos anuais: valem para todas as viagens do ano, cada uma com até 30 dias.')
      titulo = comparacao.index('Se você viaja mais vezes no ano')
      expect(comparacao.index('Especial UA 100K BRL')).to be < titulo
      expect(comparacao.index('Anual UA 150')).to be > titulo
      expect(comparacao.index('Anual UA 300')).to be > titulo
    end

    it 'anual nunca é a econômica, a recomendada nem a de maior cobertura, e fica fora do porquê da capa' do
      planos.push(anual('Anual UA 150', '150.0'))
      expect(texto).to include('Opção mais recomendada para esta viagem', 'Mais econômica',
                               'Por R$ 150,00 a mais que a opção mais barata, a proteção para médico e hospital sobe de ' \
                               'R$ 30.000 para R$ 100.000.')
      expect(texto).not_to include('Maior cobertura')
      expect(normalizar(leitor.pages[0].text)).not_to include('Anual UA')
    end

    it 'só anuais: a capa trata como hoje, sem a seção à parte' do
      planos.replace([anual('Anual UA 150', '150.0'), anual('Anual UA 300', '600.0')])
      expect(texto).to include('Opção mais recomendada para esta viagem', 'Anual UA 150')
      expect(texto).not_to include('Se você viaja mais vezes no ano')
    end

    it 'despesas médicas do destino internacional (2899) saem com o valor, nunca "não informado"' do
      planos.replace([anual('Anual UA 300', '600.0')])
      expect(texto).to include('$300.000 para médico e hospital por R$ 600,00 no total.')
      expect(texto).not_to include('não informado')
    end
  end

  describe 'destaques e anuais não pedidos (#3226)' do
    let(:planos) do
      [['P1', 'Especial UA 250K BRL', '540.0', 'R$ 250.000'], ['P2', 'Especial UA 30K BRL', '210.0', 'R$ 30.000'],
       ['P3', 'Especial UA 100K BRL', '360.0', 'R$ 100.000'], ['P4', 'Especial UA 60K BRL', '285.0', 'R$ 60.000']]
        .map do |codigo, nome, preco, valor|
          { 'codigo' => codigo, 'nome' => nome, 'preco_total' => preco, 'max_parcelas' => 12, 'idade_minima' => 0,
            'idade_maxima' => 65, 'faixas' => [{ 'de' => 0, 'ate' => 65, 'valor' => preco }],
            'coberturas' => [dmh.merge('valor' => valor)] }
        end
    end
    let(:pdf) { described_class.new(cotacao: cotacao, nome_corretora: 'Corretora Exemplo') }

    it 'o destaque que o modelo lê é o mesmo selo do PDF, plano a plano' do
      nomes = Autonomia::Agents::Tools::Native::SeguroViagem::Destaques::NOMES
      do_pdf = pdf.send(:planos).pluck('codigo').zip(pdf.send(:rotulos).map { |rotulo| nomes[rotulo] }).to_h.compact
      resumo = Autonomia::Agents::Tools::Native::SeguroViagem::Planos.resumo(cotacao.planos, cotacao.pedido)
      do_resumo = resumo.reject { |plano| plano['destaque'].nil? }.to_h { |plano| [plano['codigo'], plano['destaque']] }

      expect(do_resumo).to eq(do_pdf)
      expect(do_resumo.values).to contain_exactly('mais_economica', 'mais_recomendada', 'maior_cobertura')
      expect(do_resumo['P2']).to eq('mais_economica')
      expect(do_resumo['P1']).to eq('maior_cobertura')
      recomendado = resumo.find { |plano| plano['destaque'] == 'mais_recomendada' }['nome']
      expect(normalizar(leitor.pages[0].text)).to include('Opção mais recomendada para esta viagem', recomendado)
    end

    it 'cotação sem anuais, porque o cliente não pediu: o PDF não tem a seção dos anuais' do
      expect(texto).not_to include('Se você viaja mais vezes no ano', 'Planos anuais')
    end
  end

  it 'não traz comissão, id de produto nem o código interno do plano' do
    expect(texto).not_to include('comissao', '99,9', '5382451', 'P1', 'P2')
  end
end
