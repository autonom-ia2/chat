require 'rails_helper'

# Base das planilhas dos relatórios (#1960): a tabela do Excel só abre sem reparo com cabeçalhos diferentes e não
# vazios, mesmo quando o relatório repete um nome (dois anúncios com o mesmo nome).
RSpec.describe Relatorios::Planilha do
  it 'deixa os cabeçalhos da tabela únicos e sem vazio, e o arquivo segue o schema do formato' do
    planilha = described_class.new
    colunas = ['Dia', 'Promoção', 'promoção', 'Promoção', ''].map { |titulo| { titulo: titulo, tipo: :inteiro, largura: 12 } }
    planilha.aba('Por dia', titulo: 'Por dia', contexto: 'Últimos 7 dias', colunas: colunas, linhas: [[1, 2, 3, 4, 5]])

    expect(planilha.pacote.validate).to be_empty
    aba = Roo::Excelx.new(StringIO.new(planilha.gerar)).sheet(0)
    expect(aba.row(described_class::HEADER_ROW)).to eq(['Dia', 'Promoção', 'promoção (2)', 'Promoção (3)', 'Coluna 5'])
  end
end
