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
      expect(payload['quotes_with_proposal']).to be_zero
      expect(payload['proposals_issued']).to be_zero
    end

    # TERMO 3 pela API: COTAÇÕES que viraram proposta, e a soma dos códigos em separado. Uma cotação
    # com duas propostas é uma cotação — o número da fatura não pode dobrar por causa da soma.
    it 'responde cotações com proposta e propostas emitidas como dois numeros' do
      cotacao!(handle: { 'quote_id' => 'q1', 'seguradoras_acionadas' => dezessete,
                         Autonomia::Agents::Tools::Native::InsuranceQuote::PROPOSTAS_KEY => %w[8 3] })

      get base, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload['quotes_with_proposal']).to eq(1)
      expect(payload['proposals_issued']).to eq(2)
    end

    # A RECUSA DO `start` NÃO É COTAÇÃO, e a linha aqui é a que o job grava de verdade: `pedido`,
    # intenção anotada e `autonomia_submitted`, sem `quote_id`. Contá-la seria cobrar por trabalho
    # que não houve; e ela também não é "sem confirmação" — o `start` respondeu, dizendo que não fez.
    it 'nao conta como cotação a recusa que o job registrou' do
      cotacao!(handle: { 'pedido' => 'Para cotar, preciso da placa.', 'motivo' => 'faltam_dados',
                         'faltando' => ['vehicle.plate'],
                         Autonomia::Agents::ToolRun::SUBMITTED_KEY => true, Autonomia::Agents::ToolRun::INTENCOES => 1 })

      get base, headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(payload['quotes']).to be_zero
      expect(payload['insurers_called']).to be_zero
      expect(payload['unknown']['quotes_without_confirmation']).to be_zero
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

    # A JANELA TEM DUAS BORDAS. A operação pede setembro (`from=2026-09-01&to=2026-09-30`) e a
    # cotação de 01/10 é da fatura de outubro: um `to` ignorado não deixa a conta vazia, deixa ela
    # MAIOR — e número inflado em fatura ninguém questiona.
    it 'nao conta cotação feita depois do fim da janela' do
      # Arrange
      cotacao!(handle: { 'quote_id' => 'setembro', 'seguradoras_acionadas' => dezessete },
               criada_em: Time.zone.parse('2026-09-15 10:00'))
      cotacao!(handle: { 'quote_id' => 'outubro', 'seguradoras_acionadas' => dezessete },
               criada_em: Time.zone.parse('2026-10-01 09:00'))

      # Act
      get "#{base}?from=2026-09-01&to=2026-09-30", headers: admin.create_new_auth_token, as: :json

      # Assert
      payload = response.parsed_body['payload']
      expect(payload['quotes']).to eq(1)
      expect(payload['insurers_called']).to eq(17)
    end

    # NENHUM VALOR NOSSO NO LUGAR DO VALOR DE QUEM PERGUNTA: data ilegível vira recusa dita, com
    # código estável, e nunca "então são os últimos 30 dias" em silêncio.
    it 'recusa data ilegivel em vez de escolher a janela sozinho' do
      get "#{base}?from=ontem", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('periodo_invalido')
    end

    # Data-hora não é "data com precisão a mais": é pedido que a consulta não atende, e dizer isso
    # vale mais do que descartar a hora em silêncio (rodada 4).
    it 'recusa data com hora em vez de descartar a hora' do
      get "#{base}?from=2026-09-01T10:00:00&to=2026-09-30", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('periodo_invalido')
    end

    # SÓ `from`, E O DIA AINDA NÃO COMEÇOU NO FUSO DA CONTA: `from=2026-09-11` à 01h UTC, corretora em
    # São Paulo (ainda 22h de 10/09). Pela porta da conta é 422 — a data inicial dela está no futuro —
    # e a frase diz isso, em vez de acusar uma "final" que ninguém mandou (rodada 5).
    it 'recusa data inicial no futuro dizendo que ela esta no futuro' do
      account.update!(reporting_timezone: 'America/Sao_Paulo')

      travel_to Time.utc(2026, 9, 11, 1, 0) do
        get "#{base}?from=2026-09-11", headers: admin.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('periodo_invalido')
      expect(response.parsed_body['detail']).to eq('a data inicial está no futuro')
    end

    # SÓ `to`: a janela padrão termina nele. Até a rodada 4 o início padrão era ancorado em HOJE e um
    # `to` no passado voltava 422 culpando "a data inicial" — que ninguém tinha mandado.
    it 'so to: a janela padrao termina nele' do
      get "#{base}?to=2026-06-30", headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload']
      expect(response).to have_http_status(:ok)
      expect(payload['to']).to eq(Time.zone.parse('2026-06-30').end_of_day.iso8601)
      expect(payload['from']).to eq(Time.zone.parse('2026-05-31').beginning_of_day.iso8601)
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
