require 'rails_helper'

# Verificação de WhatsApp em lote no servidor (#678, frente C): cobre o telefone do Google e o WhatsApp achado no
# site, sem depender da aba aberta. O cliente WAHA é o real; só o HTTP passa pelo WebMock.
RSpec.describe Autonomia::Prospecting::VerifyWhatsappJob do
  let(:account) { create(:account) }
  let(:waha_url) { 'https://waha.test' }
  let(:waha_env) { { 'WAHA_API_URL' => waha_url, 'WAHA_API_KEY' => 'chave-waha-teste' } }
  let(:check_url) { "#{waha_url}/api/contacts/check-exists" }
  let(:queued_marker) { { 'whatsapp_verification' => { 'status' => 'queued', 'queued_at' => Time.current.iso8601 } } }
  let!(:google_lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'places/google', name: 'Clinica Google',
      phone: '(41) 99999-0000', metadata: queued_marker
    )
  end
  let!(:site_lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'places/site', name: 'Clinica Site',
      phone: '(41) 3333-4444', enriched_whatsapp: '(41) 98888-7777', metadata: queued_marker
    )
  end

  before do
    create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'sessao-prospeccao' })
    allow(Autonomia::Prospecting::LeadBroadcaster).to receive(:updated)
  end

  def stub_check(phone, exists)
    stub_request(:get, check_url)
      .with(query: { phone: phone, session: 'sessao-prospeccao' })
      .to_return(status: 200, body: { numberExists: exists }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def perform(ids)
    with_modified_env(waha_env) { described_class.perform_now(account.id, ids) }
  end

  it 'verifica o telefone do Google e o WhatsApp do site no mesmo lote e avisa a tela por lead' do
    stub_check('+5541999990000', true)
    stub_check('+554133334444', false)
    stub_check('+5541988887777', true)

    perform([google_lead.id, site_lead.id])

    expect(google_lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('verified')
    expect(site_lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('not_whatsapp')
    expect(site_lead.metadata['site_whatsapp_verification']).to include('status' => 'verified', 'phone' => '+5541988887777')
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: google_lead.id))
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: site_lead.id))
  end

  it 'o número do site confirmado vira o botão de WhatsApp quando o do Google não é WhatsApp' do
    stub_check('+554133334444', false)
    stub_check('+5541988887777', true)

    perform([site_lead.id])

    payload = Autonomia::Prospecting::LeadPayload.new(account: account).build(site_lead.reload)
    expect(payload[:whatsapp_verified]).to be(true)
    expect(payload[:whatsapp_url]).to eq('https://wa.me/5541988887777')
  end

  it 'não consulta de novo o que já foi verificado' do
    google_lead.update!(metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5541999990000' } })

    perform([google_lead.id])

    expect(a_request(:get, check_url).with(query: hash_including({}))).not_to have_been_made
  end

  it 'falha do WAHA num lead fica gravada e não derruba o resto do lote' do
    stub_request(:get, check_url).with(query: { phone: '+5541999990000', session: 'sessao-prospeccao' }).to_return(status: 500, body: '{}')
    stub_check('+554133334444', true)
    stub_check('+5541988887777', true)

    expect { perform([google_lead.id, site_lead.id]) }.not_to raise_error

    expect(google_lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('failed')
    expect(site_lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('verified')
  end

  it 'lead apagado enquanto o WAHA responde não derruba o resto do lote' do
    stub_request(:get, check_url)
      .with(query: { phone: '+5541999990000', session: 'sessao-prospeccao' })
      .to_return do
        Autonomia::Prospecting::Lead.where(id: google_lead.id).delete_all
        { status: 200, body: { numberExists: true }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
    stub_check('+554133334444', true)
    stub_check('+5541988887777', true)

    expect { perform([google_lead.id, site_lead.id]) }.not_to raise_error

    expect(Autonomia::Prospecting::Lead.exists?(google_lead.id)).to be(false)
    expect(site_lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('verified')
    expect(Autonomia::Prospecting::LeadBroadcaster).not_to have_received(:updated).with(have_attributes(id: google_lead.id))
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: site_lead.id))
  end

  it 'lead apagado antes de um erro do verificador não derruba o resto do lote' do
    allow(Autonomia::Prospecting::WhatsappVerifier).to receive(:new).and_call_original
    allow(Autonomia::Prospecting::WhatsappVerifier).to receive(:new).with(hash_including(lead: have_attributes(id: google_lead.id))) do
      Autonomia::Prospecting::Lead.where(id: google_lead.id).delete_all
      instance_double(Autonomia::Prospecting::WhatsappVerifier).tap do |verifier|
        allow(verifier).to receive(:perform).and_raise(Autonomia::Prospecting::WhatsappVerifier::Error, 'session_missing')
      end
    end
    stub_check('+554133334444', true)
    stub_check('+5541988887777', true)

    expect { perform([google_lead.id, site_lead.id]) }.not_to raise_error

    expect(site_lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('verified')
  end

  it 'solta a marca de fila quando o lead não tem telefone válido' do
    google_lead.update!(phone: '1234')

    perform([google_lead.id])

    expect(google_lead.reload.metadata).not_to have_key('whatsapp_verification')
    expect(Autonomia::Prospecting::LeadBroadcaster).to have_received(:updated).with(have_attributes(id: google_lead.id))
  end

  it 'só toca leads da conta do lote' do
    other = Autonomia::Prospecting::Lead.create!(
      account: create(:account), provider: 'mock', provider_place_id: 'places/outra', name: 'Outra', phone: '(41) 99999-1111'
    )

    perform([other.id])

    expect(a_request(:get, check_url).with(query: hash_including({}))).not_to have_been_made
  end
end
