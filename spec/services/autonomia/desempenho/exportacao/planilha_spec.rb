require 'rails_helper'

# Planilha do painel de desempenho (#2226), lida de volta com Roo. A fixture é inventada (loja genérica).
RSpec.describe Autonomia::Desempenho::Exportacao::Planilha do
  let(:painel) { JSON.parse(Rails.root.join('spec/fixtures/files/desempenho/contrato.json').read) }
  let(:planilha) { described_class.new(painel) }
  let(:arquivo) { I18n.with_locale(:pt_BR) { Roo::Excelx.new(StringIO.new(planilha.gerar)) } }

  it 'segue o schema do formato e traz as abas na ordem' do
    I18n.with_locale(:pt_BR) { expect(planilha.pacote.validate).to be_empty }
    expect(arquivo.sheets).to eq(['Resumo', 'Por dia', 'Por tema', 'Funil', 'Origem', 'Anúncios', 'Horários', 'Procuras',
                                  'Vendas perdidas', 'Detalhes do pedido', 'Regras quebradas', 'Recomendações', 'Como ler'])
  end

  it 'mantém as larguras do mapa e da conferência mesmo com a tabela de texto embaixo' do
    abas = I18n.with_locale(:pt_BR) { planilha.pacote.workbook.worksheets.index_by(&:name) }

    expect(abas['Horários'].column_info.first(3).map(&:width)).to eq([18, 5.5, 5.5])
    expect(abas['Como ler'].column_info.first(2).map(&:width)).to eq([30, 10])
    expect(abas['Horários'].page_setup.orientation).to eq(:landscape)
    expect(abas['Resumo'].page_setup.orientation).to eq(:landscape)
  end

  it 'chama a IA pelo nome, explica a coluna Grupo e repete o cabeçalho na impressão' do
    procuras = arquivo.sheet('Procuras')

    expect(procuras.row(4)).to include('Como Agente foi')
    expect(procuras.cell(2, 1)).to include('A coluna Grupo inclui fechamentos fora de Pedidos de compra')
    titulos = I18n.with_locale(:pt_BR) { planilha.pacote.workbook.defined_names.map(&:name) }
    expect(titulos).to include('_xlnm.Print_Titles')
  end

  it 'diz as datas das sugestões quando elas são de outras datas, como a tela (#2301)' do
    painel['meta']['recomendacoes_de'] = { 'inicio' => '2026-10-10', 'fim' => '2026-10-16' }

    expect(arquivo.sheet('Recomendações').cell(2, 1)).to include('sugestões de 10/10 a 16/10/2026')
  end

  it 'marca em cada procura se era pedido de compra e traz a lista completa das perdas' do
    # O Roo troca a aba ativa a cada `sheet`: confere uma antes de abrir a outra.
    expect(arquivo.sheet('Procuras').row(4)).to include('Pedidos de compra')
    expect(arquivo.sheet('Vendas perdidas').last_row - 4).to eq(painel['perdas']['lista'].size)
  end

  it 'calcula o resumo com fórmulas vivas sobre as outras abas' do
    resumo = arquivo.sheet('Resumo')

    expect(resumo.cell(4, 1)).to eq('Procuras')
    expect(resumo.formula(4, 2)).to include("SUBTOTAL(109,'Por dia'!B5:B34)")
    expect(resumo.formula(5, 11)).to include('E5-H5')
    expect(resumo.formula(6, 2)).to include("COUNTIF('Procuras'!")
  end

  it 'acha a etapa da procura pelos marcos da etapa, com o id como reserva, como o funil e a tela' do
    painel['funil']['etapas'] = [{ 'id' => 'pedido_feito', 'nome' => 'Pediu', 'marcos' => [] },
                                 { 'id' => 'etapa_x', 'nome' => 'Etapa com outro nome', 'marcos' => %w[marco_y marco_z] }]
    painel['procuras'].first['marcos'] = ['marco_z']
    painel['procuras'].second['marcos'] = ['pedido_feito']
    textos = arquivo.sheet('Procuras').to_a.flatten.compact.map(&:to_s)

    expect(textos).to include('Etapa com outro nome', 'Pediu')
  end

  it 'diz em Recomendações de que período é cada ganho' do
    painel['recomendacoes'].first['ganho'] = { 'fechamentos' => 19, 'valor' => nil, 'conta' => 'x', 'historico' => true,
                                               'periodo' => { 'inicio' => '2026-06-25', 'fim' => '2026-10-26', 'dias' => 124 } }
    recomendacoes = arquivo.sheet('Recomendações')
    coluna = recomendacoes.row(4).index('De que período é o ganho') + 1

    expect(recomendacoes.cell(5, coluna)).to eq('Neste período ainda não dá para estimar. Histórico completo: 4 meses (25/06 a 26/10)')
  end

  it 'monta o mapa 7 × 24 com a coluna e a linha Total por fórmula' do
    horarios = arquivo.sheet('Horários')

    expect(horarios.row(4)).to eq(['Dia', *(0..23).map(&:to_s), 'Total'])
    expect((5..11).map { |linha| horarios.cell(linha, 1) }).to eq(%w[Segunda Terça Quarta Quinta Sexta Sábado Domingo])
    expect(horarios.cell(5, 12)).to eq(10) # segunda, 10h (coluna B = 0h)
    expect(horarios.formula(5, 26)).to include('SUM(B5:Y5)')
    expect(horarios.cell(12, 1)).to eq('Total')
    expect(horarios.formula(12, 2)).to include('SUM(B5:B11)')
  end

  it 'lista uma linha por procura real (sem testes) com os nomes do catálogo' do
    procuras = arquivo.sheet('Procuras')
    reais = painel['procuras'].reject { |procura| procura['teste'] }

    expect(procuras.last_row - 4).to eq(reais.size)
    expect(procuras.row(4).first(4)).to eq(%w[Quando Conversa Procura Tema])
    expect(procuras.column(4).drop(4)).to all(be_present)
    expect(procuras.column(4).drop(4)).not_to include('Sem nome')
  end
end
