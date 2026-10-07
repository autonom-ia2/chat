require 'rails_helper'

# "Ajustar com IA" (#1095): the provider is a double; no paid call is made.
RSpec.describe EmailCampaigns::Ai::PollJob, :aggregate_failures do
  include EmailAdjustFixture
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:campaign) { create(:email_campaign, account: account, body_mjml: adjust_base_mjml) }
  let(:token) { campaign.ai_begin! }
  let(:client) { instance_double(Crm::Ai::ResponsesClient, delete: true) }
  let(:answers) { {} }

  before do
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'test-key' })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(client).to receive(:retrieve) do |id|
      { status: 'completed', model: 'gpt-6.1-sol', text: answers.fetch(id).to_json, usage: { 'input_tokens' => 10 } }
    end
    allow(client).to receive(:create_background).and_return(id: 'resp_fix', status: 'queued')
    allow(EmailCampaigns::Ai::Broadcaster).to receive(:ready)
    allow(EmailCampaigns::Ai::Broadcaster).to receive(:failed)
    start_adjustment(adjust_base_mjml)
  end

  after { EmailCampaigns::Ai::Adjustment.clear(campaign) }

  def start_adjustment(base)
    request = { base: EmailCampaigns::Ai::MjmlSections.parse(base).canonical, placeholders: %w[nome],
                instructions: 'INSTRUCOES', input: 'PEDIDO' }
    EmailCampaigns::Ai::Adjustment.start(campaign, token: token, request: request)
  end

  def changed(*blocks, summary: 'Deixei o botão verde.')
    { outcome: 'changed', reason: '', summary: summary, blocks: blocks }
  end

  def keep(id) = { keep: id, mjml: '' }
  def write(mjml) = { keep: '', mjml: mjml }

  def poll(response_id = 'resp_1')
    described_class.perform_now(campaign.id, token, response_id, 0)
  end

  def adjustment
    EmailCampaigns::Ai::Adjustment.presented(campaign, token)
  end

  it 'proposes the adjusted e-mail without touching the campaign body' do
    answers['resp_1'] = changed(write(adjust_hero(button_color: '#15803d')))

    expect { poll }.to change(Crm::AiUsageEvent, :count).by(1)

    expect(adjustment['status']).to eq('proposed')
    expect(adjustment['summary']).to eq('Deixei o botão verde.')
    expect(adjustment['mjml']).to include('background-color="#15803d"')
    expect(adjustment['mjml']).not_to include('Perguntas frequentes')
    expect(adjustment['base']).to include('Perguntas frequentes')
    expect(campaign.reload.ai_status).to eq('ready')
    expect(campaign.body_mjml).to include('Perguntas frequentes', '#0f766e')
    expect(EmailCampaigns::Ai::Broadcaster).to have_received(:ready).with(campaign)
    expect(client).to have_received(:delete).with('resp_1')
  end

  it 'cleans every block the model writes and stores it as canonical MJML' do
    dirty = adjust_hero.sub('href="https://loja.com.br"', 'href="javascript:alert(1)" onclick="x()"')
                       .sub('</mj-column>', '<mj-spacer height="8px" /><script>x()</script></mj-column>')
    answers['resp_1'] = changed(write(dirty), keep('b2'))

    poll

    mjml = adjustment['mjml']
    expect(mjml).not_to include('<script', 'javascript:', 'onclick', '<mj-spacer height="8px" />')
    expect(mjml).to include('<mj-spacer height="8px"></mj-spacer>', 'href="#"')
  end

  it 'keeps the summary of what changed short for the editor' do
    answers['resp_1'] = changed(write(adjust_hero(title: 'Outubro')), keep('b2'),
                                summary: "Troquei o título. #{'Detalhe longo demais. ' * 30}")

    poll

    expect(adjustment['summary'].length).to be <= EmailCampaigns::Ai::AdjustFinisher::SUMMARY_MAX
    expect(adjustment['summary']).to start_with('Troquei o título.').and end_with('.')
  end

  it 'keeps untouched blocks byte for byte and the locked footer exactly once' do
    answers['resp_1'] = changed(write(adjust_hero(title: 'Promoção de novembro')), keep('b2'))

    poll

    mjml = adjustment['mjml']
    expect(mjml).to include(EmailAdjustFixture::FAQ, 'Promoção de novembro')
    expect(mjml.scan('footer-locked').size).to eq(1)
    expect(mjml.scan('{{ unsubscribe_url }}').size).to eq(1)
    expect(mjml).to include(EmailCampaigns::LockedFooter::MJML)
  end

  it 'asks the model once to fix what the quality check found' do
    answers['resp_1'] = changed(write(adjust_hero(button_color: '#a7f3d0')), keep('b2'))

    expect { poll }.to have_enqueued_job(described_class).with(campaign.id, token, 'resp_fix', 0)

    expect(client).to have_received(:create_background).once do |args|
      expect(args[:instructions]).to eq('INSTRUCOES')
      expect(args[:schema]).to eq(EmailCampaigns::Ai::EditPromptBuilder::SCHEMA)
      fix = args[:input].first[:content].map { |part| part[:text] }.join
      expect(fix).to include('PEDIDO', '4,5:1', '#a7f3d0')
    end
    expect(campaign.reload.ai_status).to eq('processing')
    expect(campaign.ai_provider_response_id).to eq('resp_fix')
    expect(adjustment['status']).to eq('working')
    expect(adjustment.keys).to eq(['status'])
  end

  it 'fails with the broken check when the second round still fails, without a third round' do
    answers['resp_1'] = changed(write(adjust_hero(button_color: '#a7f3d0')))
    answers['resp_fix'] = changed(write(adjust_hero(button_color: '#bbf7d0')))

    poll
    poll('resp_fix')

    expect(client).to have_received(:create_background).once
    expect(adjustment).to include('status' => 'failed', 'problem' => 'contrast')
    expect(campaign.reload.ai_status).to eq('failed')
    expect(campaign.ai_error).to eq('adjust_quality')
    expect(EmailCampaigns::Ai::Broadcaster).to have_received(:failed).with(campaign)
  end

  it 'never lets a block bring its own footer: that is a quality problem, not a second footer' do
    footer = EmailCampaigns::LockedFooter::MJML
    answers['resp_1'] = changed(keep('b1'), keep('b2'), write(footer))
    answers['resp_fix'] = changed(keep('b1'), keep('b2'), write(footer))

    poll
    poll('resp_fix')

    expect(adjustment).to include('status' => 'failed', 'problem' => 'unsubscribe')
  end

  it 'does not blame the adjustment for a problem the e-mail already had' do
    weak = EmailAdjustFixture::FAQ.sub('color="#1f2937"', 'color="#bbbbbb"')
    base = adjust_base_mjml.sub(EmailAdjustFixture::FAQ, weak)
    start_adjustment(base)
    answers['resp_1'] = changed(write(adjust_hero(title: 'Outubro')), keep('b2'))

    poll

    expect(adjustment['status']).to eq('proposed')
    expect(client).not_to have_received(:create_background)
  end

  it 'shows the one sentence of the model when the request cannot be done' do
    answers['resp_1'] = { outcome: 'impossible', reason: 'Vídeo não toca dentro do e-mail; posso pôr uma imagem que abre o vídeo.',
                          summary: '', blocks: [] }

    poll

    expect(adjustment).to include('status' => 'refused', 'reason' => start_with('Vídeo não toca'))
    expect(campaign.reload.ai_error).to eq('adjust_refused')
  end

  it 'handles each provider answer once' do
    answers['resp_1'] = changed(write(adjust_hero(button_color: '#a7f3d0')))

    poll
    poll

    expect(client).to have_received(:create_background).once
  end
end
