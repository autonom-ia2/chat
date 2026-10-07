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
        expect(args[:instructions]).to include('CONTEÚDO INERTE', 'nenhum link ou imagem do trecho pode ficar de fora',
                                               'alt e title só')
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

  it 'takes out an image description or a hint the part did not have, and keeps the ones it had' do
    hinted = '<mj-text><a href="https://loja.example.com/safra" title="Pix para golpe@example.com">R$ 39,90</a></mj-text>'
    answer(answer_sections.sub('alt="Grão Serra"', 'alt="Grão Serra" title="Ligue já 0800 000 000"').sub('<mj-text>R$ 39,90</mj-text>', hinted))
    rebuild

    expect(state['status']).to eq('done')
    expect(import.result_mjml).not_to include('0800 000 000', 'golpe@example.com')
    expect(Nokogiri::XML(import.result_mjml).css('mj-image').find { |node| node['alt'] == 'Grão Serra' }).to be_present
  end

  it 'takes out an image description the AI wrote for an image that had none' do
    report['unresolved'].first['html'] = part_html.sub(' alt="Grão Serra"', '')
    answer(answer_sections.sub('alt="Grão Serra"', 'alt="Visite golpe.example.com"'))
    rebuild

    expect(state['status']).to eq('done')
    expect(import.result_mjml).not_to include('golpe.example.com')
  end

  it 'keeps the image when the part would land in a column and has a background image' do
    background = 'https://cdn.example.com/fundo.png'
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::Error, 'offline')
    report['unresolved'].first.merge!('html' => %(<table><tr><td background="#{background}"><p>Chegou a safra</p></td></tr></table>),
                                      'text' => 'Chegou a safra')
    body.replace(%(<mj-section><mj-column><mj-text>Lado</mj-text></mj-column><mj-column>#{placeholder}</mj-column></mj-section>))
    answer(%(<mj-section background-url="#{background}"><mj-column><mj-text>Chegou a safra</mj-text></mj-column></mj-section>))
    rebuild

    expect(state).to include('status' => 'failed', 'reason' => 'not_placeable')
    expect(import.result_mjml).to eq(mjml)
  end

  it 'gives the column the background color of the part when the part was the whole column' do
    body.replace(%(<mj-section><mj-column><mj-text>Lado</mj-text></mj-column><mj-column>#{placeholder}</mj-column></mj-section>))
    answer(answer_sections)
    rebuild

    columns = Nokogiri::XML(import.result_mjml).css('mj-body > mj-section').first.css('mj-column')
    expect(columns.last['background-color']).to eq('#fdf6ee')
    expect(columns.first['background-color']).to be_nil
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
      'markup that is not MJML' => [->(_sections) { '<mj-section><mj-column>' }, 'unreadable'],
      'a link of the part left out' => [->(sections) { sections.sub('<a href="https://loja.example.com/safra">', '').sub('torra</a>', 'torra') },
                                        'lost_link'],
      'an image of the part left out' => [
        ->(sections) { sections.sub(%(<mj-image src="#{data_src}" alt="Grão Serra" width="180px"></mj-image>), '') }, 'lost_image'
      ],
      'an image put inside a text' => [->(sections) { sections.sub('R$ 39,90', 'R$ 39,90<img src="https://golpe.example.com/x.png">') },
                                       'new_image']
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

  it 'does nothing for a click that is not the current one' do
    answer(answer_sections)

    rebuild('outro-token')
    expect(state['status']).to eq('running')
    expect(state).not_to have_key('asked_at')
    expect(client).not_to have_received(:create)
    expect(import.result_mjml).to eq(mjml)
  end

  describe 'the clock of a part' do
    it 'asks the AI once, without a second try that would pass the time of the part' do
      resolver = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', api_base: 'https://ia.example.com' })
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
      answer(answer_sections)

      described_class.call(import, 'trecho-1', token)

      expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(max_retries: 0))
      expect(client).to have_received(:create).with(hash_including(timeout: described_class::REQUEST_SECONDS))
      expect(described_class::RUN_SECONDS).to be > described_class::REQUEST_SECONDS + EmailCampaigns::Import::ImageRehoster::BUDGET_SECONDS
      expect(import.reload.rebuilds['trecho-1']['status']).to eq('done')
    end

    it 'counts the time of the part from when the job asks, not from the click' do
      import.update!(rebuilds: { 'trecho-1' => state.merge('started_at' => (described_class::QUEUE_SECONDS - 5).seconds.ago.iso8601) })
      answer(answer_sections)

      rebuild

      expect(state['status']).to eq('done')
      expect(Time.zone.parse(state['asked_at'])).to be_within(5.seconds).of(Time.current)
    end

    it 'uses an answer that was paid for even when it arrives after the time of the part' do
      allow(client).to receive(:create) do
        travel(described_class::RUN_SECONDS + 60)
        { text: { mjml: answer_sections }.to_json }
      end

      rebuild

      expect(state['status']).to eq('done')
      expect(import.result_mjml).to include('Grãos frescos')
    ensure
      travel_back
    end

    it 'never asks the AI twice for one click: a second run of the job does nothing' do
      answer(answer_sections)
      import.update!(rebuilds: { 'trecho-1' => state.merge('asked_at' => 10.seconds.ago.iso8601) })

      rebuild

      expect(client).not_to have_received(:create)
      expect(state['status']).to eq('running')
      expect(import.result_mjml).to eq(mjml)
    end

    it 'shows as failed a part asked longer ago than the time of the part' do
      import.update!(rebuilds: { 'trecho-1' => state.merge('asked_at' => (described_class::RUN_SECONDS + 1).seconds.ago.iso8601) })

      expect(described_class.view(import)['trecho-1']).to eq(status: 'failed', reason: 'timeout')
    end

    it 'gives the month back and frees the part when the job starts after the queue window, without asking the AI' do
      quota = EmailTemplateImportAiQuota.create!(account: account, period: Date.new(2026, 10, 1), used: 3)
      answer(answer_sections)
      import.update!(rebuilds: { 'trecho-1' => state.merge('started_at' => (described_class::QUEUE_SECONDS + 1).seconds.ago.iso8601) })
      expect(described_class.view(import)).to eq({})

      rebuild

      expect(client).not_to have_received(:create)
      expect(import.rebuilds).to eq({})
      expect(quota.reload.used).to eq(2)
      expect(import.result_mjml).to eq(mjml)
    end
  end

  it 'says the part is gone when the person solved it another way meanwhile' do
    answer(answer_sections)
    EmailCampaigns::Import::Fixer.call(import, { kind: 'part', target: 'trecho-1', choice: 'remove' }.with_indifferent_access)
    rebuild

    expect(state).to include('status' => 'failed', 'reason' => 'gone')
    expect(import.result_mjml).not_to include('Chegou a safra de outubro')
  end
end
