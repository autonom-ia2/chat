require 'rails_helper'

# #1427 — "Lendo a página X de N…": o OCR do PDF escaneado anota no material a página que começa a ler, só enquanto lê;
# N são as páginas que vão ser lidas (até o teto do OCR), não o total do PDF. A escrita segue a guarda da leitura (mesmo
# token e ainda lendo) e a chave sai quando a leitura termina, falha ou é superada.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Pdf do
  let(:account) { create(:account).tap { |conta| Autonomia::Agents::Fase2.ligar!(conta) } }
  let(:agente) { Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support') }
  let(:source) do
    material = agente.sources.new(account: account, source_type: 'pdf', reference: 'catalogo.pdf')
    material.file.attach(io: StringIO.new('pdf-bytes'), filename: 'catalogo.pdf', content_type: 'application/pdf')
    material.save!
    material
  end
  let(:rasterizacao) { Autonomia::Agents::Knowledge::Processors::Rasterizacao }
  let(:ocr) { Autonomia::Agents::Knowledge::Processors::Ocr }
  let(:visto) { [] }

  # Páginas A4 sem texto (abaixo de OCR_MIN_CHARS: vai ao OCR).
  def stub_pages(quantas)
    objetos = instance_double(PDF::Reader::ObjectHash)
    allow(objetos).to receive(:deref) { |valor| valor }
    pagina = instance_double(PDF::Reader::Page, text: ' ', attributes: { MediaBox: [0, 0, 595, 842] }, objects: objetos)
    allow(PDF::Reader).to receive(:new).and_return(instance_double(PDF::Reader, pages: [pagina] * quantas))
    allow(Autonomia::Agents::Knowledge::Processors::PdfTrechos).to receive(:da_pagina).and_return([])
  end

  def progresso_no_banco
    Autonomia::Agents::Source.find(source.id).metadata['progresso']
  end

  before do
    stub_const('Autonomia::Agents::Knowledge::Processors::PdfOcr::MAX_PAGINAS_OCR', 2)
    stub_pages(3)
    allow(rasterizacao).to receive(:pagina) do |_pdf, indice, **, &bloco|
      visto << progresso_no_banco
      bloco.call("/tmp/pagina-#{indice}.png")
    end
    allow(ocr).to receive(:ler).and_return('TEXTO RECONHECIDO VIA OCR DO SCAN')
  end

  it 'records page X of N in the database before each page, keeping the rest of the metadata' do
    source.begin_ingestion!

    described_class.new(source).extract

    expect(visto).to eq([{ 'pagina' => 1, 'total' => 2 }, { 'pagina' => 2, 'total' => 2 }])
    expect(Autonomia::Agents::Source.find(source.id).metadata).to have_key('prev_review')
  end

  it 'clears the progress when the reading ends' do
    token = source.begin_ingestion!
    described_class.new(source).extract

    source.mark_ready!(token, chunk_count: 1)

    expect(source.reload.metadata).not_to have_key('progresso')
  end

  it 'clears the progress when the reading fails, even with nothing left out' do
    stub_pages(2) # sem páginas de fora: sem o progresso, esta escrita nem tocaria o metadata
    token = source.begin_ingestion!
    described_class.new(source).extract

    source.mark_failed!(token, 'ingestion_error')

    expect(source.reload.metadata).not_to have_key('progresso')
  end

  # A instância que fecha a leitura foi carregada antes da anotação (o progresso está só no banco): mesmo assim a chave sai.
  { 'fails' => ->(fonte, token) { fonte.mark_failed!(token, 'ingestion_error') },
    'restores the previous generation' => ->(fonte, token) { fonte.restore_previous_generation!(token) } }.each do |caso, fechar|
    it "clears the progress written by another instance when the reading #{caso}" do
      token = source.begin_ingestion!
      carregada_antes = Autonomia::Agents::Source.find(source.id)
      Autonomia::Agents::Source.find(source.id).anotar_progresso!(pagina: 3, total: 30)
      expect(progresso_no_banco).to eq('pagina' => 3, 'total' => 30)

      expect(fechar.call(carregada_antes, token)).to be(true)

      expect(progresso_no_banco).to be_nil
    end

    it "keeps a key written by someone else in the meantime when the reading #{caso}" do
      token = source.begin_ingestion!
      carregada_antes = Autonomia::Agents::Source.find(source.id)
      Autonomia::Agents::Source.find(source.id).anotar_progresso!(pagina: 3, total: 30)
      outra = Autonomia::Agents::Source.find(source.id)
      outra.update!(metadata: outra.metadata.merge('mime' => 'application/pdf'))

      expect(fechar.call(carregada_antes, token)).to be(true)

      metadata = Autonomia::Agents::Source.find(source.id).metadata
      expect(metadata).to include('mime' => 'application/pdf', 'prev_review' => be_a(Hash))
      expect(metadata).not_to have_key('progresso')
    end
  end

  it 'writes nothing from a reading that another one superseded' do
    source.begin_ingestion!
    Autonomia::Agents::Source.find(source.id).begin_ingestion!

    expect(source.anotar_progresso!(pagina: 1, total: 2)).to be(false)
    expect(progresso_no_banco).to be_nil
  end

  it 'starts a new reading without the progress of the one before' do
    source.begin_ingestion!
    source.anotar_progresso!(pagina: 1, total: 2)

    Autonomia::Agents::Source.find(source.id).begin_ingestion!

    expect(progresso_no_banco).to be_nil
  end

  it 'shows the progress in the API only while reading' do
    source.begin_ingestion!
    source.anotar_progresso!(pagina: 1, total: 2)
    parcial = 'api/v1/accounts/autonomia/agents/sources/source'
    json = ->(fonte) { JSON.parse(ApplicationController.render(partial: parcial, locals: { source: fonte }, formats: [:json])) }

    expect(json.call(source.reload).dig('metadata', 'progresso')).to eq('pagina' => 1, 'total' => 2)
    travel(Autonomia::Agents::Source::TETO_DA_RELEITURA + 1.minute) do # parado: ainda processing, mas sem avançar
      expect(json.call(source.reload)['metadata']).not_to have_key('progresso')
    end
    source.update!(status: :ready)
    expect(json.call(source.reload)['metadata']).not_to have_key('progresso')
  end

  it 'records nothing outside the Fase 2 (no OCR there)' do
    Autonomia::Agents::Fase2.desligar!(account)
    source.begin_ingestion!

    described_class.new(source).extract

    expect(visto).to be_empty
    expect(progresso_no_banco).to be_nil
  end
end
