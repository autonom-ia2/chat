require 'rails_helper'

# #2896 — os exemplos de uma planilha de "Trazer minha lista", lidos na hora do arquivo conferido (30 dias). Sem o arquivo
# não há exemplo. As linhas com problema têm arquivo próprio: spec/services/contact_imports/trazer/linhas_com_problema_spec.rb.
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

  describe '#exemplos' do
    it 'traz as primeiras pessoas aprovadas, com o telefone como vai ser gravado' do
      expect(described_class.new(lida).exemplos).to eq(
        [
          { linha: 2, nome: 'Ana Albuquerino', telefone: '+5511987650001', email: 'ana@exemplo.com.br', empresa: '' },
          { linha: 3, nome: 'João Brandolim', telefone: '+5511987650002', email: '', empresa: '' }
        ]
      )
    end

    it 'lê por registro: a quebra de linha dentro de uma célula não corta o exemplo' do
      importacao = lida
      # O validador grava o nome e a empresa numa linha só; o leitor dos exemplos não depende disso.
      texto = CSV.generate do |csv|
        csv << CampaignImports::AudienceValidator::AUDIENCE_NORMALIZED_HEADERS
        csv << [2, "Ana\nAlbuquerino", "'+5511987650001", 'hash', '', '', "Padaria\nBom Dia", 0]
        (3..6).each { |numero| csv << [numero, "Pessoa #{numero}", "'+551198765000#{numero}", 'hash', '', '', '', 0] }
      end
      importacao.normalized_csv.attach(io: StringIO.new(texto), filename: 'conferido.csv', content_type: 'text/csv')

      exemplos = described_class.new(importacao.reload).exemplos

      expect(exemplos.pluck(:linha)).to eq([2, 3, 4])
      expect(exemplos.first).to include(nome: "Ana\nAlbuquerino", telefone: '+5511987650001', empresa: "Padaria\nBom Dia")
    end

    it 'só mostra o registro que veio inteiro no trecho lido do arquivo' do
      importacao = lida
      # O trecho acaba no meio do telefone da segunda pessoa.
      stub_const("#{described_class}::COMECO_DO_ARQUIVO", importacao.normalized_csv.download.index('+5511987650002') + 5)

      expect(described_class.new(importacao).exemplos.pluck(:linha, :telefone)).to eq([[2, '+5511987650001']])
    end

    # B6: o trecho que não fecha como CSV devolve o que foi lido e deixa rastro no log, sem nada do conteúdo.
    it 'devolve os registros lidos e registra no log quando o trecho não fecha como CSV' do
      importacao = lida
      inteiro = importacao.normalized_csv.download.force_encoding(Encoding::UTF_8).lines.first(2).join
      importacao.normalized_csv.attach(io: StringIO.new("#{inteiro}3,\"Bruno sem fechar\n"), filename: 'normalized.csv', content_type: 'text/csv')
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(importacao.reload).exemplos.pluck(:linha)).to eq([2])
      aviso = "[Relacionamentos::Trazer::LinhasDaPlanilha] import_id=#{importacao.id} CSV::MalformedCSVError"
      expect(Rails.logger).to have_received(:warn).with(aviso)
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
