require 'rails_helper'

# #2896 — os valores inteiros de uma planilha de "Trazer minha lista", lidos na hora: só as linhas pedidas da planilha
# original (7 dias) e os exemplos do arquivo conferido (30 dias). Sem o arquivo, nada inteiro sai daqui.
RSpec.describe Relacionamentos::Trazer::LinhasDaPlanilha, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:planilha) { "Nome;Celular;E-mail\nAna Albuquerino;11987650001;ana@exemplo.com.br\nJoão Brandolim;11987650002;\nCarla;123;\n" }

  def lida(texto = planilha, **dados)
    importacao = create_contact_import(account: account, user: user, content: texto, **dados)
    importacao.update!(options: importacao.options.merge('trazer' => {}))
    ContactImports::Validator.new(importacao).perform
    importacao.reload
  end

  describe '#ler' do
    it 'devolve só as linhas pedidas, pelo número que elas têm na planilha' do
      linhas = described_class.new(lida).ler([4, 2])

      expect(linhas).to eq(2 => ['Ana Albuquerino', '11987650001', 'ana@exemplo.com.br'], 4 => ['Carla', '123', ''])
    end

    it 'deixa o bloco pedir mais linhas da mesma leitura' do
      planilha_lida = described_class.new(lida)

      linhas = planilha_lida.ler([4]) do |achadas|
        expect(achadas.keys).to eq([4])
        [3, 4, nil]
      end

      expect(linhas.keys).to contain_exactly(3, 4)
      expect(linhas[3]).to eq(['João Brandolim', '11987650002', ''])
    end

    it 'para na última linha pedida: o resto da planilha nem é lido' do
      importacao = lida
      quebrada = "#{planilha}Davi;\"aspa que nunca fecha;\n"
      importacao.original_file.attach(io: StringIO.new(quebrada), filename: 'contatos.csv', content_type: 'text/csv')

      expect(described_class.new(importacao).ler([2])).to eq(2 => ['Ana Albuquerino', '11987650001', 'ana@exemplo.com.br'])
      expect { described_class.new(importacao).ler([5]) }.to raise_error(CSV::MalformedCSVError)
    end

    it 'lê a planilha que não veio em UTF-8 como a leitura a leu' do
      importacao = lida(planilha.encode(Encoding::Windows_1252))

      expect(importacao.campaign_import_rows.find_by!(row_number: 3).raw_name).to eq('João Brandolim')
      expect(described_class.new(importacao).ler([3])).to eq(3 => ['João Brandolim', '11987650002', ''])
    end

    it 'lê as linhas pedidas de um XLSX' do
      xlsx = build_xlsx([%w[Nome Celular], ['Ana Albuquerino', '11987650001'], ['João Brandolim', '11987650002'], %w[Carla 123]])
      importacao = lida(xlsx, filename: 'contatos.xlsx',
                              content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')

      expect(importacao).to have_attributes(status: 'ready_to_confirm', valid_rows: 2, invalid_rows: 1)
      expect(described_class.new(importacao).ler([4, 3])).to eq(3 => ['João Brandolim', '11987650002'], 4 => %w[Carla 123])
    end

    it 'não abre arquivo nenhum quando nenhuma linha é pedida' do
      importacao = lida
      allow(importacao.original_file).to receive(:download).and_call_original

      expect(described_class.new(importacao).ler([])).to eq({})
      expect(importacao.original_file).not_to have_received(:download)
    end

    it 'não tem o que devolver depois que a planilha original foi apagada' do
      importacao = lida
      importacao.original_file.purge
      planilha_lida = described_class.new(importacao)

      expect(planilha_lida).not_to be_inteira
      expect(planilha_lida.ler([2, 4])).to eq({})
    end
  end

  describe '#exemplos' do
    it 'traz as primeiras pessoas aprovadas, com o telefone como vai ser gravado' do
      expect(described_class.new(lida).exemplos).to eq(
        [
          { nome: 'Ana Albuquerino', telefone: '+5511987650001', email: 'ana@exemplo.com.br', empresa: '', cliente: false },
          { nome: 'João Brandolim', telefone: '+5511987650002', email: '', empresa: '', cliente: false }
        ]
      )
    end

    it 'continua trazendo os exemplos depois que só a planilha original foi apagada' do
      importacao = lida
      importacao.original_file.purge

      expect(described_class.new(importacao).exemplos.pluck(:telefone)).to eq(['+5511987650001', '+5511987650002'])
    end

    it 'fica vazio depois que o arquivo conferido foi apagado' do
      importacao = lida
      importacao.normalized_csv.purge

      expect(described_class.new(importacao).exemplos).to eq([])
    end
  end
end
