require 'rails_helper'

# PDF 16:9 do painel de desempenho (#2226), lido de volta com PDF::Reader. A fixture é inventada (loja genérica).
RSpec.describe Autonomia::Desempenho::Exportacao::Pdf do
  let(:painel) { JSON.parse(Rails.root.join('spec/fixtures/files/desempenho/contrato.json').read) }
  let(:servico) { described_class.new(painel) }
  let(:leitor) { I18n.with_locale(:pt_BR) { PDF::Reader.new(StringIO.new(servico.gerar)) } }

  def texto(numero)
    leitor.page(numero).text.squish
  end

  def pagina_de(secao)
    servico.paginas_da_secao(secao).first
  end

  it 'gera uma página 16:9 por item do plano, com o índice de cada seção' do
    expect(leitor.page_count).to eq(servico.paginas.size)
    expect(leitor.page(1).attributes[:MediaBox]).to eq([0, 0, 960, 540])
    # capa, evolução, funil, temas, origem, horários, qualidade, pessoa, perdas, 1 de ações, 2 de como ler,
    # 2 por período (30 dias / 19), 1 por tema, 1 de regras, 3 de perdas (36 / 16) e 1 de conversas ativas.
    expect(servico.paginas.size).to eq(20)
    expect(texto(1)).to include('Evolução 02', 'Horários 06', 'Tabelas 13–20', 'Página 01 de 20')
  end

  it 'traz na capa os 8 números com o rótulo, o valor e a ressalva do resultado' do
    capa = texto(1)

    expect(capa).to include('Procuras', 'Conversas', 'Pedidos de compra', 'Fecharam', 'Dúvidas resolvidas',
                            'Ficaram sem uma pessoa', 'Vendas perdidas por causa corrigível', 'Tempo para Agente responder')
    expect(capa).to include('231', '131', '135', '25', '70,8%', '32', '36', '31 s')
    expect(capa).to include('▲ 14 a mais que no período anterior', 'Link de pagamento enviado não prova que a pessoa pagou.')
    expect(capa).to include('Volume', 'Maior trava', 'Por onde começar')
    expect(capa).to include('Datas e horários no fuso da sua conta (America/Sao Paulo)')
  end

  it 'diz o fuso uma vez no arquivo, na capa, e não no rodapé de cada página' do
    expect(texto(1)).to include('America/Sao Paulo')
    expect((2..leitor.page_count).map { |numero| texto(numero) }.join(' ')).not_to include('America/Sao Paulo')
  end

  it 'começa pela sugestão de maior ganho no período e diz de que datas é o ganho' do
    primeira, segunda = painel['recomendacoes'].first(2)
    primeira.merge!('pronto' => 'ja_da', 'titulo' => 'Sugestão do histórico',
                    'ganho' => { 'fechamentos' => 19, 'valor' => nil, 'conta' => 'x', 'historico' => true,
                                 'periodo' => { 'inicio' => '2026-06-25', 'fim' => '2026-10-26', 'dias' => 124 } })
    segunda.merge!('pronto' => 'ja_da', 'titulo' => 'Sugestão do período',
                   'ganho' => { 'fechamentos' => 4, 'valor' => nil, 'conta' => 'y', 'historico' => false,
                                'periodo' => { 'inicio' => '2026-09-27', 'fim' => '2026-10-26', 'dias' => 30 } })

    # O PDF::Reader intercala as colunas da capa: a frase pode ser cortada pela de outro cartão no meio.
    expect(texto(1)).to include('Sugestão do período. Ganho estimado: ≈ 4 vendas em 30 dias (27/09 a')
    expect(texto(1)).not_to include('Sugestão do histórico')
    acoes = Range.new(*servico.paginas_da_secao(:acoes)).map { |numero| texto(numero) }.join(' ')
    expect(acoes).to include('Ganho estimado: neste período ainda não dá para', 'no histórico completo (4 meses, 25/06 a 26/10)')
  end

  it 'diz as datas das sugestões quando elas são de outras datas, como a tela (#2301)' do
    painel['meta']['recomendacoes_de'] = { 'inicio' => '2026-10-10', 'fim' => '2026-10-16' }

    acoes = Range.new(*servico.paginas_da_secao(:acoes)).map { |numero| texto(numero) }.join(' ')

    expect(acoes).to include('Sugestões de 10/10 a 16/10/2026.')
  end

  it 'mostra o número dentro das células do mapa de calor e o pico' do
    mapa = texto(pagina_de(:horarios))

    expect(mapa).to include('Pico · Segunda 10h', 'Mais · máximo 10', 'Horário comercial: Seg a Sex, 9h às 18h')
  end

  it 'fecha cada página da tabela por período com o total do trecho e marca o dia em andamento' do
    primeira, ultima = servico.paginas_da_secao(:tabela_periodo)

    expect(texto(primeira)).to include('Números por período (1/2)', 'Total do trecho')
    expect(texto(ultima)).to include('26/10/2026*', '* dia ainda em andamento', 'Total do trecho')
  end

  it 'compara anúncio e sem anúncio com a mesma conta quando a conta tem anúncios' do
    expect(texto(pagina_de(:origem))).to include('Veio de anúncio', 'Chegou sem anúncio', '20,0% fecham', '18,0% fecham')
  end

  context 'without anúncio ligado na conta' do
    let(:painel) do
      dados = JSON.parse(Rails.root.join('spec/fixtures/files/desempenho/contrato.json').read)
      dados['meta']['anuncios_ligados'] = false
      dados['origem'] = dados['origem'].merge('anuncios_ligados' => false, 'comparacao' => nil, 'anuncios' => [])
      dados
    end

    it 'mostra como chegaram (com quanto fechou em cada grupo) e a frase calma, sem repetir a taxa num segundo cartão' do
      origem = texto(pagina_de(:origem))

      expect(origem).to include('Como chegaram', 'fecharam (', 'Esta conta não tem anúncio ligado.')
      expect(origem).not_to include('Veio de anúncio', 'Quem fecha mais')
    end
  end

  it 'põe quanto confiar numa página própria, com a leitura geral e cada campo otimista' do
    primeira, segunda = servico.paginas_da_secao(:como_ler)

    expect(segunda).to eq(primeira + 1)
    expect(texto(primeira)).to include('O que estes números não provam')
    expect(texto(segunda)).to include('Quanto confiar', 'A qualidade do agente saiu otimista.', 'Otimista', 'Firme')
  end

  it 'deixa "não atuou" fora da base da qualidade e chama a IA pelo nome' do
    expect(texto(pagina_de(:qualidade))).to include('fora da base', 'Como Agente atuou', 'Como Agente atende')
  end

  it 'explica por que o último passo do funil e "fecharam" não dão o mesmo número' do
    painel['funil']['conciliacao'] = { 'chegaram_ao_fim' => 13, 'chegaram_e_nao_fecharam' => 1, 'fecharam_sem_chegar' => 5,
                                       'fecharam' => 17 }

    expect(texto(pagina_de(:funil))).to include('1 chegou a este passo e não terminou em', '5 terminaram em')
  end

  it 'calcula o "N× mais" pela conta exata, não pelos % arredondados' do
    # 10/39 ÷ 7/201 = 7,36 (os % arredondados, 25,6 ÷ 3,5, dariam 7,3).
    painel['comparacoes'] = [{ 'id' => 'x', 'recorte' => 'origem', 'ressalva' => nil,
                               'a' => { 'nome' => 'Grupo A', 'n' => 10, 'm' => 39, 'pct' => 25.6 },
                               'b' => { 'nome' => 'Grupo B', 'n' => 7, 'm' => 201, 'pct' => 3.5 } }]

    expect(texto(pagina_de(:funil))).to include('7,4× mais')
  end

  it 'calcula os pontos de diferença pela conta exata e só compara com base suficiente dos dois lados' do
    # 2/45 − 1/24 = 0,28 ponto (os % arredondados, 4,4 − 4,2, dariam 0,2).
    painel['comparacoes'] = [{ 'id' => 'x', 'recorte' => 'origem', 'ressalva' => nil,
                               'a' => { 'nome' => 'Grupo A', 'n' => 2, 'm' => 45, 'pct' => 4.4 },
                               'b' => { 'nome' => 'Grupo B', 'n' => 1, 'm' => 24, 'pct' => 4.2 } },
                             { 'id' => 'y', 'recorte' => 'marco', 'ressalva' => nil,
                               'a' => { 'nome' => 'Grupo C', 'n' => 1, 'm' => 3, 'pct' => 33.3 },
                               'b' => { 'nome' => 'Grupo D', 'n' => 16, 'm' => 199, 'pct' => 8.0 } }]
    funil = texto(pagina_de(:funil))

    expect(funil).to include('0,3 ponto')
    expect(funil).to include('Poucos casos para comparar')
  end

  it 'traduz as partes que usam o período todo, com o "e" do idioma e sem id cru' do
    painel['avisos'] = [{ 'id' => 'so_periodo_todo', 'valores' => { 'secoes' => %w[confianca ticket] } }]
    como_ler = texto(pagina_de(:como_ler))

    expect(como_ler).to include('Esta parte usa o período todo: a conferência (“Quanto confiar”) e o valor típico de uma venda.')
    expect(como_ler).not_to include(' and ', 'confianca', 'ticket.')
  end

  it 'não corta a conta do ganho em silêncio: o que não cabe termina em reticências' do
    longa = Array.new(400) { |indice| "palavra#{indice}" }.join(' ')
    painel['recomendacoes'].first['ganho'] = { 'fechamentos' => 3, 'valor' => 900, 'conta' => longa }
    paginas = servico.paginas_da_secao(:acoes)
    acoes = Range.new(*paginas).map { |numero| texto(numero) }.join(' ')

    expect(acoes).to include('Como calculamos: palavra0', '…')
    expect(acoes).not_to include('palavra399')
  end

  it 'recusa contrato de outra versão' do
    expect { described_class.new(painel.merge('versao' => 1)) }
      .to raise_error(Autonomia::Desempenho::Exportacao::Contrato::Invalido)
  end
end
