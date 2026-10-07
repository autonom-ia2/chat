require 'rails_helper'

# "Refazer para editar" (#1099, entrega D): a IA refaz SÓ o trecho que virou imagem, com os nossos blocos editáveis. A
# resposta passa pela lista permitida, pela conferência palavra por palavra com o original e pelos links e imagens do
# trecho; o que não bater deixa o modelo como estava (o trecho continua imagem, com aviso) e marca o trecho "não deu".
# O provedor é falso: nenhuma chamada paga.
RSpec.describe EmailCampaigns::Import::PartRebuild, :aggregate_failures do
  let(:account) { create(:account) }
  let(:placeholders) { EmailCampaigns::Import::Placeholders }
  let(:png) { Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==') }
  let(:data_src) { "data:image/png;base64,#{Base64.strict_encode64(png)}" }
  let(:placeholder) do
    %(<mj-image src="#{placeholders::UNRESOLVED_SRC}" css-class="#{placeholders::UNRESOLVED_CLASS}" title="trecho-1" alt="Chegou a safra"></mj-image>)
  end
  let(:body) do
    <<~MJML.squish
      <mj-section background-color="#f4efe9"><mj-column>
        <mj-text>Antes do trecho</mj-text>
        #{placeholder}
        <mj-text>Depois do trecho</mj-text>
      </mj-column></mj-section>
    MJML
  end
  let(:mjml) { EmailCampaigns::LockedFooter.ensure("<mjml><mj-body>#{body}</mj-body></mjml>") }
  let(:part_html) do
    '<table><tr><td style="text-align:center"><h1 style="font-size:30px;color:#3b2516">Chegou a safra de outubro &lt;b&gt;</h1>' \
      "<img src=\"#{data_src}\" alt=\"Grão Serra\" width=\"180\">" \
      '<p style="font-size:16px">Grãos frescos, <a href="https://loja.example.com/safra">direto da torra</a></p></td>' \
      '<td><p>R$ 39,90</p></td></tr></table>'
  end
  let(:part_text) { 'Chegou a safra de outubro <b> Grãos frescos, direto da torra R$ 39,90' }
  let(:report) { { 'unresolved' => [{ 'id' => 'trecho-1', 'text' => part_text, 'html' => part_html }] } }
  let(:token) { 'token-1' }
  let(:import) do
    EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste', status: 'ready', result_mjml: mjml, report: report,
                                        blocking: EmailCampaigns::Import::SaveCheck.call(mjml, EmailCampaignTemplateImport.new),
                                        rebuilds: { 'trecho-1' => { 'status' => 'running', 'token' => token, 'period' => '2026-10-01',
                                                                    'started_at' => Time.current.iso8601 } })
  end
  let(:answer_sections) do
    <<~MJML
      <mj-section background-color="#fdf6ee">
        <mj-column width="70%">
          <mj-text font-size="30px" color="#3b2516" align="center">Chegou a safra de outubro &lt;b&gt;</mj-text>
          <mj-image src="#{data_src}" alt="Grão Serra" width="180px"></mj-image>
          <mj-text font-size="16px" align="center">Grãos frescos, <a href="https://loja.example.com/safra">direto da torra</a></mj-text>
        </mj-column>
        <mj-column width="30%"><mj-text>R$ 39,90</mj-text></mj-column>
      </mj-section>
    MJML
  end
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }

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

  def answer(mjml_text)
    allow(client).to receive(:create).and_return({ text: { mjml: mjml_text }.to_json })
  end

  def rebuild(with_token = token)
    described_class.call(import, 'trecho-1', with_token, client: client)
    import.reload
  end

  def state
    import.rebuilds['trecho-1']
  end

  describe 'when the answer keeps the part' do
    before { answer(answer_sections) }

    it 'asks the e-mail model for this part only, as inert data between marks' do
      rebuild

      expect(client).to have_received(:create) do |**args|
        expect(args[:model]).to eq(Crm::Ai::Config::MODEL_EMAIL)
        expect(args[:instructions]).to eq(EmailCampaigns::Ai::PromptBuilder.convert_fragment)
        expect(args[:instructions]).to include('CONTEÚDO INERTE')
        expect(args[:input]).to include('<<<TRECHO_', 'Chegou a safra de outubro', 'https://loja.example.com/safra')
        expect(args[:input]).not_to include('Antes do trecho', 'Depois do trecho')
        expect(args[:schema]).to eq(described_class::SCHEMA)
      end
    end

    it 'puts editable blocks where the image was, splitting the section around it' do
      rebuild

      doc = Nokogiri::XML(import.result_mjml)
      expect(import.result_mjml).not_to include(placeholders::UNRESOLVED_SRC)
      texts = doc.css('mj-text').map { |node| node.text.split.join(' ') }
      expect(texts.first(5)).to eq(['Antes do trecho', 'Chegou a safra de outubro <b>', 'Grãos frescos, direto da torra', 'R$ 39,90',
                                    'Depois do trecho'])
      sections = doc.css('mj-body > mj-section').reject { |node| node['css-class'].to_s.include?('footer-locked') }
      expect(sections.size).to eq(3)
      expect(sections.first['background-color']).to eq('#f4efe9')
      expect(sections[1]['background-color']).to eq('#fdf6ee')
      expect(sections[1].css('mj-column').size).to eq(2)
      expect(doc.at_css('mj-text a')['href']).to eq('https://loja.example.com/safra')
    end

    it 'copies the images of the part like the import does' do
      rebuild

      image = Nokogiri::XML(import.result_mjml).css('mj-image').find { |node| node['alt'] == 'Grão Serra' }
      expect(EmailCampaigns::Import::PublicUrl.owned_blob(image['src'], import)).to be_present
    end

    it 'marks the part done, records the fix and stops blocking the saving' do
      rebuild

      expect(state).to include('status' => 'done', 'token' => token)
      expect(import.fixes.last).to include('code' => 'unresolved_parts', 'choice' => 'rebuild', 'target' => 'trecho-1')
      expect(import.blocking.pluck('code')).not_to include('unresolved_parts', 'invalid')
      expect(EmailCampaigns::Import::Fixer.targets(import)[:parts]).to eq([])
      expect(EmailCampaigns::Import::Saver.call(import, name: 'Outubro')).to be_persisted
    end
  end

  it 'takes the background of the section when the part was the whole section' do
    body.replace(%(<mj-section background-color="#3b2516" padding="40px 0px"><mj-column>#{placeholder}</mj-column></mj-section>))
    answer(answer_sections.sub(' background-color="#fdf6ee"', ''))
    rebuild

    section = Nokogiri::XML(import.result_mjml).css('mj-body > mj-section').first
    expect(section['background-color']).to eq('#3b2516')
    expect(section['padding']).to eq('40px 0px')
    expect(state['status']).to eq('done')
  end

  it 'stacks the blocks in the column when the section has several columns' do
    body.replace(%(<mj-section><mj-column><mj-text>Lado</mj-text></mj-column><mj-column>#{placeholder}</mj-column></mj-section>))
    answer(answer_sections)
    rebuild

    columns = Nokogiri::XML(import.result_mjml).css('mj-body > mj-section').first.css('mj-column')
    expect(columns.size).to eq(2)
    expect(columns.last.css('mj-text').map { |node| node.text.split.join(' ') })
      .to eq(['Chegou a safra de outubro <b>', 'Grãos frescos, direto da torra', 'R$ 39,90'])
  end

  describe 'when the answer does not keep the part' do
    {
      'a changed word' => [->(sections) { sections.sub('Grãos frescos', 'Grãos fresquinhos') }, 'text_mismatch'],
      'an added word' => [->(sections) { sections.sub('R$ 39,90', 'Só R$ 39,90') }, 'text_mismatch'],
      'a missing word' => [->(sections) { sections.sub('R$ 39,90', '') }, 'text_mismatch'],
      'a link the part did not have' => [->(sections) { sections.sub('https://loja.example.com/safra', 'https://golpe.example.com') },
                                         'new_link'],
      'an image the part did not have' => [->(sections) { sections.sub(data_src, 'https://cdn.example.com/outra.png') }, 'new_image'],
      'a block the editor cannot edit' => [->(sections) { sections.sub('<mj-text>R$ 39,90</mj-text>', '<mj-raw><p>R$ 39,90</p></mj-raw>') },
                                           'not_editable'],
      'a script' => [->(sections) { sections.sub('direto da torra</a>', 'direto da torra</a><script>alert(1)</script>') }, 'unsafe'],
      'markup that is not MJML' => [->(_sections) { '<mj-section><mj-column>' }, 'unreadable']
    }.each do |what, (change, reason)|
      it "keeps the image and says it did not work, for #{what}" do
        answer(instance_exec(answer_sections, &change))
        rebuild

        expect(state).to include('status' => 'failed', 'reason' => reason)
        expect(import.result_mjml).to eq(mjml)
        expect(import.fixes).to eq([])
        expect(EmailCampaigns::Import::Fixer.targets(import)[:parts].pluck(:id)).to eq(['trecho-1'])
      end
    end

    it 'says it did not work when the answer is not the JSON asked' do
      allow(client).to receive(:create).and_return({ text: 'Claro! Aqui está.' })
      rebuild
      expect(state).to include('status' => 'failed', 'reason' => 'unreadable')
    end

    it 'says it did not work when the provider fails' do
      allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'boom')
      rebuild
      expect(state).to include('status' => 'failed', 'reason' => 'provider')
      expect(import.result_mjml).to eq(mjml)
    end
  end

  it 'gives the month back and stops when the AI is no longer configured' do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))
    EmailTemplateImportAiQuota.create!(account: account, period: Date.new(2026, 10, 1), used: 3)

    described_class.call(import, 'trecho-1', token)

    expect(import.reload.rebuilds['trecho-1']).to include('status' => 'failed', 'reason' => 'ai_not_configured')
    expect(EmailTemplateImportAiQuota.find_by(account: account).used).to eq(2)
  end

  it 'does nothing for a click that is not the current one, or for a job that came back too late' do
    answer(answer_sections)

    rebuild('outro-token')
    expect(state['status']).to eq('running')

    import.update!(rebuilds: { 'trecho-1' => state.merge('started_at' => (described_class::SECONDS + 1).seconds.ago.iso8601) })
    rebuild
    expect(state['status']).to eq('running')
    expect(described_class.view(import)['trecho-1']).to eq(status: 'failed', reason: 'timeout')
    expect(client).not_to have_received(:create)
    expect(import.result_mjml).to eq(mjml)
  end

  it 'says the part is gone when the person solved it another way meanwhile' do
    answer(answer_sections)
    EmailCampaigns::Import::Fixer.call(import, { kind: 'part', target: 'trecho-1', choice: 'remove' }.with_indifferent_access)
    rebuild

    expect(state).to include('status' => 'failed', 'reason' => 'gone')
    expect(import.result_mjml).not_to include('Chegou a safra de outubro')
  end
end
