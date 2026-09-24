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
end
