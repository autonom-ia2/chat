require 'rails_helper'

# #3198 — o copiloto e o Guia leem apresentação. Os bytes são um .pptx de verdade (zip com um XML por slide), montado
# aqui: exercita a leitura real do zip e do XML.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Pptx do
  subject(:processor) { described_class.new(source) }

  # ActiveStorage delega #download dinamicamente (method_missing -> blob); verified double não o vê.
  let(:source) { double('source', reference: 'deck.pptx', source_type: 'pptx', file: file) } # rubocop:disable RSpec/VerifiedDoubles
  let(:file) { double('attachment', attached?: true, download: pptx_bytes) } # rubocop:disable RSpec/VerifiedDoubles
  let(:arquivos) { {} }
  let(:pptx_bytes) { build_pptx(arquivos) }

  def build_pptx(entradas)
    tmp = Tempfile.new(['fixture', '.pptx'])
    tmp.close
    Zip::File.open(tmp.path, Zip::File::CREATE) do |zip|
      entradas.each { |nome, conteudo| zip.get_output_stream(nome) { |out| out.write(conteudo) } }
    end
    bytes = File.binread(tmp.path)
    tmp.unlink
    bytes
  end

  def slide(*paragrafos)
    corpo = paragrafos.map { |texto| "<a:p><a:r><a:t>#{texto}</a:t></a:r></a:p>" }.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
        <p:cSld><p:spTree><p:sp><p:txBody>#{corpo}</p:txBody></p:sp></p:spTree></p:cSld>
      </p:sld>
    XML
  end

  describe '#extract' do
    context 'with several slides' do
      let(:arquivos) do
        {
          'ppt/slides/slide10.xml' => slide('Contato'),
          'ppt/slides/slide2.xml' => slide('Planos', 'Bronze e Prata'),
          'ppt/slides/slide1.xml' => slide('Seguro Viagem GTA'),
          'ppt/slides/_rels/slide1.xml.rels' => '<Relationships/>'
        }
      end

      it 'lê os slides na ordem do número, um parágrafo por linha' do
        expect(processor.extract).to eq(
          "Slide 1:\nSeguro Viagem GTA\n\nSlide 2:\nPlanos\nBronze e Prata\n\nSlide 3:\nContato"
        )
      end
    end

    context 'with a slide without text' do
      let(:arquivos) { { 'ppt/slides/slide1.xml' => slide, 'ppt/slides/slide2.xml' => slide('Só este tem texto') } }

      it 'pula o slide vazio' do
        expect(processor.extract).to eq("Slide 2:\nSó este tem texto")
      end
    end

    context 'without slides' do
      let(:arquivos) { { 'ppt/presentation.xml' => '<p:presentation/>' } }

      it 'falha com motivo' do
        expect { processor.extract }.to raise_error(Autonomia::Agents::Knowledge::Processors::Base::ExtractionError, 'pptx_missing_slides')
      end
    end

    context 'with a broken zip' do
      let(:pptx_bytes) { 'não é um zip' }

      it 'falha com motivo' do
        expect { processor.extract }.to raise_error(Autonomia::Agents::Knowledge::Processors::Base::ExtractionError,
                                                    a_string_starting_with('pptx_parse_failed'))
      end
    end
  end

  it 'entra pelo Dispatcher' do
    expect(Autonomia::Agents::Knowledge::Processors::Dispatcher.for(source)).to be_a(described_class)
  end
end
