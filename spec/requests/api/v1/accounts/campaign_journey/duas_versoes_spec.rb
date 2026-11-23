require 'rails_helper'

# #3099: duas versões da mensagem pela API da jornada — criar a campanha com a versão 2, o plano contado pelo
# servidor, o bloco do resultado e a escolha da versão do resto (campaign_send, idempotente).
RSpec.describe 'Campaign journey duas versões (#3099)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let!(:inbox) { journey_twilio_sms_inbox(account) }
  let(:content) do
    linhas = (0...10).map { |i| "Pessoa #{i},1198765#{format('%04d', i)}" }
    "Nome,Celular\n#{linhas.join("\n")}\n"
  end
  let(:audience) { saved_audience(account: account, user: user, content: content) }
  let(:duas_versoes) { { criterio: 'respostas', divisao: 50, espera_horas: 4, segunda: { message_body: 'Oi {{contact.first_name}}, versão 2' } } }

  before do
    stub_const('CampaignJourney::DuasVersoes::MINIMO_POR_VERSAO', 2)
    stub_const('CampaignJourney::DuasVersoes::MINIMO_NO_RESTO', 2)
  end

  def headers(as = user)
    { 'api_access_token' => as.access_token.token }
  end

  def criar(**campaign)
    body = {
      campaign_import_id: audience.id, channel: 'sms',
      campaign: { title: 'Parcela', inbox_id: inbox.id, scheduled_at: nil, message: 'Oi {{contact.first_name}}, versão 1',
                  duas_versoes: duas_versoes }.merge(campaign)
    }
    post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns", params: body, headers: headers, as: :json
    account.campaigns.find_by(id: response.parsed_body['id'])
  end

  def vencedora(campaign, versao, as: user)
    post "/api/v1/accounts/#{account.id}/campaign_journey/results/sms/#{campaign.display_id}/vencedora",
         params: { versao: versao }, headers: headers(as), as: :json
  end

  describe 'POST campaigns' do
    it 'cria a campanha com as duas versões; quem recebe agora é o teste' do
      campaign = criar

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['recipients_count']).to eq(4)
      link = CampaignAudienceLink.for_campaign(campaign)
      expect(link).to have_attributes(teste_criterio: 'respostas', teste_divisao: 50, teste_espera_horas: 4, teste_estado: 'testando',
                                      teste_resto: 6)
    end

    it 'recusa a versão 2 igual à 1 e regra fora das opções' do
      criar(duas_versoes: duas_versoes.merge(segunda: { message_body: 'Oi {{contact.first_name}}, versão 1' }))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('segunda_versao_igual')

      criar(duas_versoes: duas_versoes.merge(divisao: 60))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('invalid_campaign')
      expect(account.campaigns.count).to eq(0)
    end
  end

  describe 'POST recipient_previews' do
    def prever(**extra)
      post "/api/v1/accounts/#{account.id}/campaign_journey/recipient_previews",
           params: { campaign_import_id: audience.id, channel: 'sms', message_body: 'Oi' }.merge(extra), headers: headers, as: :json
    end

    it 'devolve o plano do teste contado sobre o "Vão receber" sem o grupo de controle' do
      prever(duas_versoes: { divisao: 50 }, grupo_de_controle_pct: 20)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'receive')).to eq(10)
      expect(response.parsed_body.dig('payload', 'duas_versoes')).to include('modo' => 'teste', 'teste' => 4, 'versao1' => 2, 'versao2' => 2,
                                                                             'resto' => 4)
    end

    it 'sem duas versões não manda plano; divisão fora das opções é recusada' do
      prever
      expect(response.parsed_body['payload']).not_to have_key('duas_versoes')

      prever(duas_versoes: { divisao: 60 })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('invalid_divisao')
    end
  end

  describe 'resultado e escolha da versão' do
    let!(:sent) { stub_twilio_sms }
    let(:campaign) { criar.tap { |created| Twilio::OneoffSmsCampaignService.new(campaign: created).perform } }

    it 'mostra as duas versões no resultado' do
      get "/api/v1/accounts/#{account.id}/campaign_journey/results/sms/#{campaign.display_id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      bloco = response.parsed_body.dig('payload', 'duas_versoes')
      expect(bloco).to include('estado' => 'testando', 'criterio' => 'respostas', 'resto' => 6, 'vencedora' => nil)
      expect(bloco['escolhe_em']).to be_within(60).of(4.hours.from_now.to_i)
      expect(bloco['versoes'].map { |versao| versao.slice('numero', 'texto', 'receberam', 'responderam') }).to eq(
        [{ 'numero' => 1, 'texto' => 'Oi {{contact.first_name}}, versão 1', 'receberam' => 2, 'responderam' => 0 },
         { 'numero' => 2, 'texto' => 'Oi {{contact.first_name}}, versão 2', 'receberam' => 2, 'responderam' => 0 }]
      )
    end

    it 'escolhe a versão do resto uma vez só: a mesma de novo responde 200, outra responde 422' do
      vencedora(campaign, 2)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include('estado' => 'escolhida', 'vencedora' => 2, 'escolhida_por' => 'voce')

      vencedora(campaign, 2)
      expect(response).to have_http_status(:ok)

      vencedora(campaign, 1)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('campaign_journey.versao_ja_escolhida')

      CampaignJourney::EnviarRestoJob.perform_now(CampaignAudienceLink.for_campaign(campaign).id)
      expect(sent.size).to eq(10)
    end

    it 'recusa versão fora de 1 e 2, campanha sem duas versões e quem não pode disparar' do
      vencedora(campaign, 3)
      expect(response).to have_http_status(:unprocessable_entity)

      sem = criar(duas_versoes: nil)
      vencedora(sem, 1)
      expect(response).to have_http_status(:not_found)

      agent, = create_crm_agent(account: account)
      vencedora(campaign, 1, as: agent)
      expect(response).to have_http_status(:unauthorized)
      expect(CampaignAudienceLink.for_campaign(campaign).teste_estado).to eq('testando')
    end
  end
end
