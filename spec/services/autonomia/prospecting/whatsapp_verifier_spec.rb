require 'rails_helper'

# Caracterização da verificação de WhatsApp antes da E0 (#683). O cliente WAHA
# é o real; só o HTTP passa pelo WebMock.
RSpec.describe Autonomia::Prospecting::WhatsappVerifier do
  let(:account) { create(:account) }
  let(:waha_url) { 'https://waha.test' }
  let(:waha_env) { { 'WAHA_API_URL' => waha_url, 'WAHA_API_KEY' => 'chave-waha-teste' } }
  let(:phone) { '(41) 99999-0000' }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/zap', name: 'Clinica Zap', phone: phone)
  end
  let(:check_url) { "#{waha_url}/api/contacts/check-exists" }

  before do
    create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'sessao-prospeccao' })
  end

  def verify
    with_modified_env(waha_env) { described_class.new(lead: lead).perform }
  end

  def stub_check(phone:, body:, status: 200)
    stub_request(:get, check_url)
      .with(query: { phone: phone, session: 'sessao-prospeccao' })
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'marca verified com o chatId devolvido pelo WAHA' do
    stub_check(phone: '+5541999990000', body: { numberExists: true, chatId: '5541999990000@c.us' })

    result = verify

    expect(result.exists).to be(true)
    expect(result.phone).to eq('+5541999990000')
    expect(result.chat_id).to eq('5541999990000@c.us')
    expect(result.lead.metadata['whatsapp_verification']).to include(
      'status' => 'verified', 'phone' => '+5541999990000', 'chat_id' => '5541999990000@c.us', 'session' => 'sessao-prospeccao'
    )
  end

  # ENRIQ-69 (#682, E6): a verificação é do número consultado. Se uma busca troca o telefone do lead enquanto o WAHA
  # responde, o resultado do número antigo não é gravado como se fosse do lead, e o lead volta à fila para o número
  # novo: a marca "queued" da consulta antiga não pode ficar presa em "Verificando" até o reaper.
  describe 'telefone trocado durante a consulta' do
    include ActiveJob::TestHelper

    def stub_check_changing_phone_to(new_phone)
      stub_request(:get, check_url)
        .with(query: { phone: '+5541999990000', session: 'sessao-prospeccao' })
        .to_return do
          Autonomia::Prospecting::Lead.where(id: lead.id).update_all(phone: new_phone) # rubocop:disable Rails/SkipsModelValidations
          { status: 200, body: { numberExists: true, chatId: '5541999990000@c.us' }.to_json, headers: { 'Content-Type' => 'application/json' } }
        end
    end

    it 'não grava o resultado do número antigo e põe o número novo na fila' do
      stub_check_changing_phone_to('(41) 98888-7777')

      result = verify

      expect(result.pending).to be(true)
      expect(result.exists).to be_nil
      expect(lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('queued')
      expect(Autonomia::Prospecting::VerifyWhatsappJob).to have_been_enqueued.with(account.id, [lead.id])
    end

    it 'solta a marca "queued" da consulta antiga e enfileira de novo, em vez de esperar o reaper' do
      lead.update!(metadata: { 'whatsapp_verification' => { 'status' => 'queued', 'queued_at' => 3.hours.ago.iso8601 } })
      stub_check_changing_phone_to('(41) 98888-7777')

      verify

      verification = lead.reload.metadata['whatsapp_verification']
      expect(verification['status']).to eq('queued')
      expect(Time.zone.parse(verification['queued_at'])).to be > 1.minute.ago
      expect(Autonomia::Prospecting::VerifyWhatsappJob).to have_been_enqueued.with(account.id, [lead.id])
    end

    it 'lead apagado durante a consulta: não grava, não enfileira e não levanta erro' do
      stub_request(:get, check_url)
        .with(query: { phone: '+5541999990000', session: 'sessao-prospeccao' })
        .to_return do
          Autonomia::Prospecting::Lead.where(id: lead.id).delete_all
          { status: 200, body: { numberExists: true }.to_json, headers: { 'Content-Type' => 'application/json' } }
        end

      result = verify

      expect(result.pending).to be(true)
      expect(result.lead).to be_nil
      expect(Autonomia::Prospecting::VerifyWhatsappJob).not_to have_been_enqueued
    end

    it 'lead apagado quando o WAHA falha: não levanta erro' do
      stub_request(:get, check_url)
        .with(query: { phone: '+5541999990000', session: 'sessao-prospeccao' })
        .to_return do
          Autonomia::Prospecting::Lead.where(id: lead.id).delete_all
          { status: 500, body: '{}' }
        end

      expect(verify.pending).to be(true)
    end

    it 'grava quando o telefone só mudou de escrita (mesmo número em E.164)' do
      stub_check_changing_phone_to('+55 41 99999-0000')

      result = verify

      expect(lead.reload.metadata['whatsapp_verification']).to include('status' => 'verified', 'phone' => '+5541999990000')
      expect(result.pending).to be_falsey
    end
  end

  it 'monta o chatId a partir do telefone quando o WAHA não devolve um' do
    stub_check(phone: '+5541999990000', body: { numberExists: 'true' })

    expect(verify.chat_id).to eq('5541999990000@c.us')
  end

  it 'marca not_whatsapp sem chat_id quando o número não existe' do
    stub_check(phone: '+5541999990000', body: { numberExists: false })

    result = verify

    expect(result.exists).to be(false)
    expect(result.chat_id).to be_nil
    expect(result.lead.metadata['whatsapp_verification']).to include('status' => 'not_whatsapp')
    expect(result.lead.metadata['whatsapp_verification']).not_to have_key('chat_id')
  end

  it 'grava failed e levanta verification_failed quando o WAHA responde com erro' do
    stub_check(phone: '+5541999990000', body: { error: 'sessao caiu' }, status: 500)

    expect { verify }.to raise_error(described_class::Error, 'prospecting.whatsapp.verification_failed')
    expect(lead.reload.metadata['whatsapp_verification']).to include('status' => 'failed', 'phone' => '+5541999990000')
    expect(lead.metadata.dig('whatsapp_verification', 'error')).to include('500')
  end

  it 'grava failed quando o WAHA não responde a tempo' do
    stub_request(:get, check_url).with(query: hash_including({})).to_timeout

    expect { verify }.to raise_error(described_class::Error, 'prospecting.whatsapp.verification_failed')
    expect(lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('failed')
  end

  describe 'normalização do telefone' do
    {
      '5541999990000' => '+5541999990000',
      '+1 (415) 555-0100' => '+14155550100',
      '41 3333-4444' => '+554133334444'
    }.each do |raw, normalized|
      context "with telefone #{raw}" do
        let(:phone) { raw }

        it "consulta o WAHA com #{normalized}" do
          stub_check(phone: normalized, body: { numberExists: false })

          expect(verify.phone).to eq(normalized)
        end
      end
    end

    context 'with DDD 55 sem código do país' do
      let(:phone) { '(55) 99988-7766' }

      it 'lê o 55 como DDD (RS) e consulta +5555999887766' do
        stub_check(phone: '+5555999887766', body: { numberExists: true })

        result = verify

        expect(result.phone).to eq('+5555999887766')
        expect(result.chat_id).to eq('5555999887766@c.us')
      end
    end

    describe 'tabela compartilhada com o front' do
      ProspectingPhoneContractCases.all.each do |item|
        context "with #{item['caso']}" do
          let(:phone) { item['raw'] }

          before { ProspectingPhoneContractCases.apply_region!(account, item['region']) }

          if item['e164']
            it "consulta o WAHA com #{item['e164']}" do
              stub_check(phone: item['e164'], body: { numberExists: false })

              expect(verify.phone).to eq(item['e164'])
            end
          else
            it 'trata como telefone ausente' do
              expect { verify }.to raise_error(described_class::Error, 'prospecting.whatsapp.phone_missing')
            end
          end
        end
      end
    end

    context 'with número curto demais' do
      let(:phone) { '1234' }

      it 'trata como telefone ausente' do
        expect { verify }.to raise_error(described_class::Error, 'prospecting.whatsapp.phone_missing')
      end
    end
  end

  describe 'pré-requisitos' do
    context 'without telefone' do
      let(:phone) { nil }

      it 'recusa com phone_missing' do
        expect { verify }.to raise_error(described_class::Error, 'prospecting.whatsapp.phone_missing')
      end
    end

    it 'recusa com waha_not_configured quando falta a URL ou a chave do WAHA' do
      expect do
        with_modified_env('WAHA_API_URL' => '', 'WAHA_API_KEY' => '') { described_class.new(lead: lead).perform }
      end.to raise_error(described_class::Error, 'prospecting.whatsapp.waha_not_configured')
    end

    it 'recusa com session_missing quando a conta não tem caixa WAHA com sessão' do
      other_account = create(:account)
      create(:channel_api, account: other_account, additional_attributes: { 'provider' => 'waha' })
      other_lead = Autonomia::Prospecting::Lead.create!(account: other_account, provider: 'mock', name: 'Sem Sessao', phone: phone)

      expect do
        with_modified_env(waha_env) { described_class.new(lead: other_lead).perform }
      end.to raise_error(described_class::Error, 'prospecting.whatsapp.session_missing')
      expect(other_lead.reload.metadata).not_to have_key('whatsapp_verification')
    end
  end

  # Registro de eventos (#732 item 13, ENRIQ-60): log estruturado com lead, conta e motivo. O número, o chat e a sessão
  # do WhatsApp nunca vão para o log.
  describe 'registro de eventos' do
    include ProspectingEventLogHelpers

    let(:personal_data) { %w[5541999990000 99999-0000 sessao-prospeccao chave-waha-teste] }

    it 'registra o número confirmado com a origem e o desfecho, sem o número nem o chat' do
      stub_check(phone: '+5541999990000', body: { numberExists: true, chatId: '5541999990000@c.us' })

      log = capture_prospecting_events { verify }

      expect(log.events).to eq(
        [{ 'event' => 'whatsapp.checked', 'lead_id' => lead.id, 'account_id' => account.id, 'source' => 'google', 'status' => 'verified' }]
      )
      expect(log.text).not_to include(*personal_data)
    end

    it 'registra o número que não é WhatsApp' do
      stub_check(phone: '+5541999990000', body: { numberExists: false })

      log = capture_prospecting_events { verify }

      expect(log.events.last).to include('event' => 'whatsapp.checked', 'status' => 'not_whatsapp')
    end

    it 'registra a falha do WAHA com a classe do erro, sem a URL que leva o número' do
      stub_request(:get, check_url).with(query: hash_including({})).to_return(status: 500, body: 'erro interno')

      log = capture_prospecting_events { expect { verify }.to raise_error(described_class::Error) }

      expect(log.events).to eq(
        [{ 'event' => 'whatsapp.failed', 'lead_id' => lead.id, 'account_id' => account.id, 'source' => 'google',
           'reason' => 'Waha::Client::Error' }]
      )
      expect(log.text).not_to include(*personal_data)
    end

    it 'registra a recusa por falta de sessão com o código' do
      log = capture_prospecting_events do
        expect { with_modified_env(waha_env.merge('WAHA_API_URL' => '')) { described_class.new(lead: lead).perform } }
          .to raise_error(described_class::Error)
      end

      expect(log.events).to eq(
        [{ 'event' => 'whatsapp.skipped', 'lead_id' => lead.id, 'account_id' => account.id, 'source' => 'google',
           'reason' => 'prospecting.whatsapp.waha_not_configured' }]
      )
    end
  end
end
