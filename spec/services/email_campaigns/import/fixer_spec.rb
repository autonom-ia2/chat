require 'rails_helper'

# As correções da tela "Veio com problemas" (#1099, entrega C): cada aviso que trava o salvamento tem uma saída feita no
# servidor, sobre a cópia que o servidor guarda — trocar ou tirar a imagem que não veio, escolher o que vai no lugar de
# um campo que não existe aqui e deixar só o texto de um trecho que virou imagem (ou tirar o trecho). Depois de cada uma,
# o que trava o salvamento é calculado de novo, e a correção fica registrada para a tela mostrar o aviso em verde.
RSpec.describe EmailCampaigns::Import::Fixer, :aggregate_failures do
  let(:account) { create(:account) }
  let(:placeholders) { EmailCampaigns::Import::Placeholders }
  let(:png) { Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==') }
  let(:body) do
    <<~MJML.squish
      <mj-section css-class="#{placeholders::MISSING_BACKGROUND_CLASS}"><mj-column><mj-text>Banner</mj-text></mj-column></mj-section>
      <mj-section><mj-column>
        <mj-image src="#{placeholders::UNRESOLVED_SRC}" css-class="#{placeholders::UNRESOLVED_CLASS}" title="trecho-1" alt="Chegou a safra"></mj-image>
        <mj-text>Olá, {{ nome }}! Seu cupom: {{ lead.cupom }}</mj-text>
        <mj-image src="#{placeholders::MISSING_SRC}" css-class="#{placeholders::MISSING_CLASS}" alt="Grão Vale"></mj-image>
        <mj-button href="https://loja.example.com" title="{{ lead.cupom }}">Quero provar</mj-button>
      </mj-column></mj-section>
    MJML
  end
  let(:mjml) { EmailCampaigns::LockedFooter.ensure("<mjml><mj-body>#{body}</mj-body></mjml>") }
  let(:part_html) do
    '<table><tr><td style="text-align:center"><h1 style="font-size:30px;color:#3b2516">Chegou a safra de outubro &lt;b&gt;</h1>' \
      '<p style="font-size:16px">Grãos frescos,<br>direto da torra</p></td></tr></table>'
  end
  let(:report) { { 'unresolved' => [{ 'id' => 'trecho-1', 'text' => 'Chegou a safra de outubro <b>', 'html' => part_html }] } }
  let(:import) do
    EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste', status: 'ready', result_mjml: mjml, report: report,
                                        blocking: EmailCampaigns::Import::SaveCheck.call(mjml, EmailCampaignTemplateImport.new))
  end

  around do |example|
    with_modified_env FRONTEND_URL: 'https://app.exemplo.com.br' do
      example.run
    end
  end

  before do
    allow(EmailCampaigns::Import::ImageCompressor).to receive(:call) do |bytes, content_type|
      EmailCampaigns::Import::ImageCompressor::Output.new(bytes: bytes, content_type: content_type, extension: 'png', compressed: false)
    end
  end

  def fix(params)
    described_class.call(import, params.with_indifferent_access)
    import.reload
  end

  def upload(bytes = png)
    file = Tempfile.new(['troca', '.png'], binmode: true)
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'image/png', true, original_filename: 'troca.png')
  end

  def codes
    import.blocking.pluck('code')
  end

  describe '.targets' do
    it 'lists what the screen can fix, in the order it appears' do
      targets = described_class.targets(import)

      expect(targets[:images]).to eq([{ index: 0, kind: 'background', alt: nil }, { index: 1, kind: 'image', alt: 'Grão Vale' }])
      expect(targets[:parts]).to eq([{ id: 'trecho-1', text: 'Chegou a safra de outubro <b>' }])
      expect(targets[:fields]).to eq(['lead.cupom'])
    end
  end

  describe 'an image that did not come' do
    it 'takes a new image, copied like the others, and stops blocking' do
      fix(kind: 'image', target: '1', choice: 'upload', file: upload)

      image = Nokogiri::XML(import.result_mjml).css('mj-image').find { |node| node['alt'] == 'Grão Vale' }
      expect(EmailCampaigns::Import::PublicUrl.owned_blob(image['src'], import)).to be_present
      expect(image['css-class'].to_s).not_to include(placeholders::MISSING_CLASS)
      expect(import.fixes.last).to include('code' => 'image_missing', 'choice' => 'upload', 'target' => 'Grão Vale', 'kind' => 'image')
      expect(described_class.targets(import)[:images].size).to eq(1)
    end

    it 'puts a new background image on the section, or leaves the section without one' do
      fix(kind: 'image', target: '0', choice: 'upload', file: upload)
      section = Nokogiri::XML(import.result_mjml).css('mj-section').first
      expect(EmailCampaigns::Import::PublicUrl.owned_blob(section['background-url'], import)).to be_present
      expect(import.fixes.last).to include('kind' => 'background')
      expect(import.fixes.last).not_to have_key('target')

      fix(kind: 'image', target: '0', choice: 'remove')
      expect(import.result_mjml).not_to include('Grão Vale', placeholders::MISSING_SRC)
      expect(codes).not_to include('image_missing')
    end

    it 'keeps nothing when the image is not there (already solved, or never was)' do
      expect { fix(kind: 'image', target: '999', choice: 'upload', file: upload) }
        .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:fix_gone) }
      fix(kind: 'image', target: '1', choice: 'remove')
      expect { fix(kind: 'image', target: '1', choice: 'upload', file: upload) }
        .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:fix_gone) }

      expect(import.reload.images.count).to eq(0)
      expect(ActiveStorage::Blob.count).to eq(0)
    end

    it 'refuses a file that is not an image, and one that is too big' do
      expect { fix(kind: 'image', target: '1', choice: 'upload', file: upload('<html>oi</html>')) }
        .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:image_unfit) }
      stub_const('EmailCampaigns::Import::Fixer::MAX_IMAGE_BYTES', 10)
      expect { fix(kind: 'image', target: '1', choice: 'upload', file: upload) }
        .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:image_too_large) }
      expect(import.reload.result_mjml).to eq(mjml)
    end
  end

  describe 'a field that does not exist here' do
    it 'becomes one of our fields everywhere it appears' do
      fix(kind: 'field', target: 'lead.cupom', choice: 'field', value: 'primeiro_nome')

      expect(import.result_mjml).to include('Seu cupom: {{ primeiro_nome }}', 'title="{{ primeiro_nome }}"')
      expect(import.result_mjml).not_to include('lead.cupom')
      expect(codes).not_to include('unknown_fields')
    end

    it 'becomes a text, the same for everyone, written as text' do
      fix(kind: 'field', target: 'lead.cupom', choice: 'text', value: '  OUTUBRO<10>  ')

      expect(import.result_mjml).to include('Seu cupom: OUTUBRO&lt;10&gt;')
      expect(import.fixes.last).to include('code' => 'unknown_fields', 'target' => 'lead.cupom', 'choice' => 'text', 'value' => 'OUTUBRO<10>')
    end

    it 'can be erased' do
      fix(kind: 'field', target: 'lead.cupom', choice: 'remove')
      expect(import.result_mjml).to include('Seu cupom: </mj-text>')
    end

    it 'refuses a field that is not ours, a text that would make a new field, and a field that is not there' do
      [
        [{ choice: 'field', value: 'senha' }, :fix_invalid],
        [{ choice: 'text', value: 'oi {{ email }}' }, :text_invalid],
        [{ choice: 'text', value: '' }, :text_invalid],
        [{ choice: 'text', value: 'x' * 201 }, :text_invalid]
      ].each do |params, code|
        expect { fix(kind: 'field', target: 'lead.cupom', **params) }
          .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(code) }
      end
      expect { fix(kind: 'field', target: 'nome', choice: 'remove') }
        .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:fix_gone) }
    end
  end

  describe 'a part that became an image' do
    it 'keeps only its text, one editable block per paragraph, the title still a title' do
      fix(kind: 'part', target: 'trecho-1', choice: 'text')

      title, first, second = Nokogiri::XML(import.result_mjml).css('mj-text')[1, 3]
      expect([title.text, first.text, second.text]).to eq(['Chegou a safra de outubro <b>', 'Grãos frescos,', 'direto da torra'])
      expect(title.to_h).to include('font-size' => '30px', 'font-weight' => '700', 'align' => 'center', 'color' => '#3b2516')
      expect(first.to_h).to include('font-size' => '16px', 'align' => 'center')
      expect(first.to_h).not_to have_key('font-weight')
      expect(import.result_mjml).to include('Chegou a safra de outubro &lt;b>')
      expect(import.result_mjml).not_to include(placeholders::UNRESOLVED_SRC)
      expect(codes).not_to include('unresolved_parts')
    end

    it 'falls back to the flat text when the report kept no markup' do
      import.update!(report: { 'unresolved' => [{ 'id' => 'trecho-1', 'text' => 'Chegou a safra' }] })
      fix(kind: 'part', target: 'trecho-1', choice: 'text')

      expect(Nokogiri::XML(import.result_mjml).css('mj-text')[1].text).to eq('Chegou a safra')
    end

    it 'stays readable on the color of the section it lands on' do
      dark = mjml.sub('<mj-section><mj-column>', '<mj-section background-color="#3b2516"><mj-column>')
      import.update!(result_mjml: dark)

      fix(kind: 'part', target: 'trecho-1', choice: 'text')

      gate = EmailCampaigns::QualityGate.new(mjml: import.result_mjml, remote_images: true,
                                             placeholders: EmailCampaigns::Import::Engine::PLACEHOLDERS)
      expect(gate.violations.map(&:check)).not_to include(:contrast)
    end

    it 'can be taken out' do
      fix(kind: 'part', target: 'trecho-1', choice: 'remove')
      expect(import.result_mjml).not_to include(placeholders::UNRESOLVED_SRC)
      expect { fix(kind: 'part', target: 'trecho-1', choice: 'remove') }
        .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:fix_gone) }
    end
  end

  it 'saves once everything is solved' do
    fix(kind: 'image', target: '0', choice: 'remove')
    fix(kind: 'image', target: '0', choice: 'upload', file: upload)
    fix(kind: 'field', target: 'lead.cupom', choice: 'text', value: 'OUTUBRO10')
    fix(kind: 'part', target: 'trecho-1', choice: 'text')

    expect(import.blocking).to eq([])
    expect(import.fixes.size).to eq(4)
    expect(EmailCampaigns::Import::Saver.call(import, name: 'Outubro')).to be_persisted
  end

  it 'only fixes an import that is ready' do
    import.update!(status: 'saved')
    expect { fix(kind: 'part', target: 'trecho-1', choice: 'remove') }
      .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:not_ready) }
    expect { described_class.call(import.tap { |record| record.update!(status: 'ready') }, { kind: 'nada' }.with_indifferent_access) }
      .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:fix_invalid) }
  end
end
