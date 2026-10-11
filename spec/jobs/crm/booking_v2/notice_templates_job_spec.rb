require 'rails_helper'

# Job de criação dos modelos de aviso na Meta (#1272), com a Meta falsa: cria e marca o estado, trata a recusa e a falta
# de permissão, e esgotadas as tentativas com a Meta fora do ar marca "falhou".
RSpec.describe Crm::BookingV2::NoticeTemplatesJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:page) { create_booking_profile(account: account, host: create(:user, account: account, role: :administrator)) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:templates_url) { "https://graph.facebook.com/v14.0/#{channel.provider_config['business_account_id']}/message_templates" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:requests) { Crm::BookingV2::NoticeTemplates::Requests.new(page: page.reload, inbox: Inbox.find(inbox.id)) }

  before do
    channel.update_columns(message_templates: []) # rubocop:disable Rails/SkipsModelValidations
    stub_request(:get, templates_url).with(query: hash_including({})).to_return(status: 200, body: { data: [] }.to_json, headers: json)
  end

  def run(kinds)
    Crm::BookingV2::NoticeTemplates::Requests.new(page: page, inbox: inbox).start!(kinds)
    perform_enqueued_jobs { described_class.perform_later(page.id, inbox.id, kinds) }
  end

  it 'cria na Meta e cada aviso passa de "enviando" a "em aprovação"' do
    stub_request(:post, templates_url).to_return(status: 200, body: { id: '1', status: 'PENDING' }.to_json, headers: json)

    run(%w[booked hour_before])

    expect(requests.states.transform_values { |entry| entry['state'] }).to eq('booked' => 'pending', 'hour_before' => 'pending')
    expect(page.reload.metadata['notice_template_requests']).to eq(inbox.id.to_s => {})
  end

  it 'recusa da Meta: o aviso fica "falhou" com o texto dela; o outro segue' do
    stub_request(:post, templates_url).to_return(
      { status: 400, body: { error: { error_user_msg: 'O texto foi recusado.', code: 100 } }.to_json, headers: json },
      { status: 200, body: { id: '2', status: 'PENDING' }.to_json, headers: json }
    )

    run(%w[booked day_before])

    expect(requests.states['booked']).to include('state' => 'failed', 'reason' => 'O texto foi recusado.')
    expect(requests.states['day_before']['state']).to eq('pending')
  end

  it 'sem permissão na Meta: "falhou" com o texto para reconectar a caixa' do
    stub_request(:post, templates_url).to_return(status: 403, body: { error: { type: 'OAuthException', code: 200 } }.to_json, headers: json)

    run(%w[booked])

    expect(requests.states['booked']['reason']).to start_with('A conexão deste WhatsApp não tem permissão para criar modelos.')
  end

  it 'Meta fora do ar: tenta de novo e, esgotadas as tentativas, marca "falhou" sem duplicar' do
    post = stub_request(:post, templates_url).to_timeout

    Crm::BookingV2::NoticeTemplates::Requests.new(page: page, inbox: inbox).start!(%w[booked])
    perform_enqueued_jobs { described_class.perform_later(page.id, inbox.id, %w[booked]) }

    expect(post).to have_been_requested.times(3)
    expect(requests.states['booked']).to include('state' => 'failed', 'reason' => 'A Meta não respondeu. Tente de novo em alguns minutos.')
  end
end
