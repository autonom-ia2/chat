require 'rails_helper'

# #1426 (t4e) — PDF grande: o texto sai também dividido em seções por faixa de páginas, para cada trecho saber de que
# páginas veio (base do resumo por seção). Só na Fase 2, fora da Lia, e só no material grande.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Pdf do
  let(:account) { create(:account) }
  let(:file) { double('attachment', attached?: true, download: 'pdf-bytes') } # rubocop:disable RSpec/VerifiedDoubles
  let(:reader) { instance_double(PDF::Reader) }
  let(:bia) { instance_double(Autonomia::Agents::Agent, instrucao_mantida?: false) }

  def material(agent: bia)
    double('source', reference: 'doc.pdf', source_type: 'pdf', file: file, account: account, agent: agent).tap do |fonte| # rubocop:disable RSpec/VerifiedDoubles
      allow(fonte).to receive(:paginas_de_fora=)
      allow(fonte).to receive(:secoes=)
    end
  end

  def stub_pages(total)
    pages = (1..total).map { |numero| instance_double(PDF::Reader::Page, runs: [], text: "Texto da pagina #{numero}") }
    allow(PDF::Reader).to receive(:new).and_return(reader)
    allow(reader).to receive(:pages).and_return(pages)
  end

  def secoes_de(source)
    capturadas = nil
    allow(source).to receive(:secoes=) { |valor| capturadas = valor }
    described_class.new(source).extract
    capturadas
  end

  context 'with a large PDF in the Fase 2' do
    before do
      Autonomia::Agents::Fase2.ligar!(account)
      stub_pages(300)
    end

    it 'splits the text in sections of consecutive pages' do
      secoes = secoes_de(material)

      expect(secoes.size).to eq(12)
      expect(secoes.first['paginas']).to eq([1, 25])
      expect(secoes.last['paginas']).to eq([276, 300])
    end

    it 'keeps the text of each page in its own section' do
      secoes = secoes_de(material)
      secao = secoes.find { |item| item['paginas'] == [251, 275] }

      expect(secao['texto']).to include('Texto da pagina 260')
      expect(secao['texto']).not_to include('Texto da pagina 250')
    end

    it 'still returns the whole text' do
      expect(described_class.new(material).extract).to include('Texto da pagina 300')
    end
  end

  it 'does not split a small PDF' do
    Autonomia::Agents::Fase2.ligar!(account)
    stub_pages(described_class::PAGINAS_DE_MATERIAL_GRANDE)
    source = material

    described_class.new(source).extract

    expect(source).not_to have_received(:secoes=)
  end

  it 'does not split outside the Fase 2' do
    stub_pages(300)
    source = material

    described_class.new(source).extract

    expect(source).not_to have_received(:secoes=)
  end

  it 'does not split for the Lia' do
    Autonomia::Agents::Fase2.ligar!(account)
    stub_pages(300)
    source = material(agent: instance_double(Autonomia::Agents::Agent, instrucao_mantida?: true))

    described_class.new(source).extract

    expect(source).not_to have_received(:secoes=)
  end
end
