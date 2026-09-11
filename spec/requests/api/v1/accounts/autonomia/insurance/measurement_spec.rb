require 'rails_helper'

# A PORTA DA MEDIDA (entrega 7, termo 4): alguém da OPERAÇÃO precisa conseguir rodar a consulta.
#
# O gate é o do módulo — feature ligada, conta marcada, administrador —, e o escopo é sempre a conta
# corrente: a medida de outra corretora não existe por esta porta.
RSpec.describe 'Autonomia Insurance Measurement API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:atendente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/insurance/measurement" }
  let(:dezessete) { %w[1 3 4 5 7 8 11 12 19 20 26 44 46 47 48 50 55] }

  def enable_feature!(enabled: true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INSURANCE_QUOTING_ENABLED', false).and_return(enabled ? 'true' : 'false')
    Autonomia::Insurance::Config.enable_for!(account) if enabled
  end

  def cotacao!(conta: account, handle: {}, criada_em: Time.current)
    agente = Autonomia::Agents::Agent.create!(account: conta, name: "Mia #{conta.id}",
                                              agent_type: 'insurance_quote', status: :active,
                                              enabled: true, instruction: 'Cote.')
    conversa = create(:conversation, account: conta, inbox: create(:inbox, account: conta))
    Autonomia::Agents::ToolRun.create!(account: conta, agent: agente, conversation_id: conversa.id,
                                       slug: Autonomia::Agents::Tools::Native::InsuranceQuote.slug,
                                       status: 'done', execution_key: SecureRandom.uuid,
                                       handle: handle, created_at: criada_em)
  end

  describe 'gate e permissão' do
    it 'esconde o recurso quando a feature esta desligada' do
      enable_feature!(enabled: false)
      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'recusa atendente comum' do
      enable_feature!
      get base, headers: atendente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET' do
    before { enable_feature! }

    # TERMO 1 e 2 — os dois números, e o número bate com o caso conhecido.
    it 'responde cotações e seguradoras acionadas' do
      # Arrange
      cotacao!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                         'entregues' => %w[1 3 4 5 7 8 11 12 19 20 26] })

      # Act
      get base, headers: admin.create_new_auth_token, as: :json

      # Assert
      payload = response.parsed_body['payload']
      expect(response).to have_http_status(:ok)
      expect(payload['quotes']).to eq(1)
      expect(payload['insurers_called']).to eq(17)
      expect(payload['insurers_with_price']).to eq(11)
      expect(payload['proposals']).to be_zero
    end

    it 'responde a janela que usou' do
      get "#{base}?from=2026-09-01&to=2026-09-30", headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload['from']).to eq(Time.zone.parse('2026-09-01').beginning_of_day.iso8601)
      expect(payload['to']).to eq(Time.zone.parse('2026-09-30').end_of_day.iso8601)
      expect(payload['timezone']).to eq(Time.zone.name)
    end

    it 'respeita o periodo pedido' do
      cotacao!(handle: { 'quote_id' => 'velha', 'seguradoras_acionadas' => dezessete }, criada_em: 40.days.ago)

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['quotes']).to be_zero
    end

    # NENHUM VALOR NOSSO NO LUGAR DO VALOR DE QUEM PERGUNTA: data ilegível vira recusa dita, com
    # código estável, e nunca "então são os últimos 30 dias" em silêncio.
    it 'recusa data ilegivel em vez de escolher a janela sozinho' do
      get "#{base}?from=ontem", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('periodo_invalido')
    end

    # Isolamento de conta: a cotação da corretora vizinha não entra no número desta.
    it 'nao mistura corretoras' do
      outra = create(:account)
      cotacao!(conta: outra, handle: { 'quote_id' => 'q2', 'seguradoras_acionadas' => dezessete })

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']['quotes']).to be_zero
      expect(response.parsed_body['payload']['insurers_called']).to be_zero
    end

    # O que não se sabe vem SEPARADO, nunca somado no total.
    it 'separa o que a medida nao sabe' do
      cotacao!(handle: { 'quote_id' => 'q1' })

      get base, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload['quotes']).to eq(1)
      expect(payload['insurers_called']).to be_zero
      expect(payload['unknown']['quotes_without_measure']).to eq(1)
    end
  end
end
