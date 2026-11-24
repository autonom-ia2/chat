require 'rails_helper'

# #3101: o "Mandar de novo" chega na criação da campanha (WhatsApp Oficial, SMS, WhatsApp API) e, no e-mail, no PUT
# email_medicoes, logo antes de enviar. Recusado, a campanha não fica criada.
RSpec.describe 'Campaign journey reenvio (#3101)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false',
                      EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:headers) { { 'api_access_token' => user.access_token.token } }

  def opcoes_de(campaign)
    Autonomia::CampanhaOpcoesDeEnvio.find_by(campanha: campaign)
  end

  context 'when creating an SMS campaign' do
    let!(:inbox) { journey_twilio_sms_inbox(account) }
    let!(:audience) { saved_audience(account: account, user: user, content: "Nome,Celular\nAna,11987654321\n") }

    def criar(**reenvio)
      post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns",
           params: { campaign_import_id: audience.id, channel: 'sms',
                     campaign: { title: 'Parcela', inbox_id: inbox.id, scheduled_at: nil, message: 'Oi', **reenvio } },
           headers: headers, as: :json
    end

    it 'saves the second message with the campaign' do
      criar(reenvio_quem: 'nao_respondeu', reenvio_dias: 3, reenvio_mensagem: { texto: 'Ainda aí?' })

      expect(response).to have_http_status(:ok)
      campaign = account.campaigns.find(response.parsed_body['id'])
      expect(opcoes_de(campaign)).to have_attributes(reenvio_quem: 'nao_respondeu', reenvio_dias: 3, reenvio_status: 'aguardando')
      # O display_id vem do banco depois do commit da transação (Campaign#set_display_id): o retorno é montado depois dele.
      expect(response.parsed_body['display_id']).to be_present
      expect(response.parsed_body['display_id']).to eq(campaign.display_id)
    end

    it 'refuses "did not read" on SMS with 422, and the campaign is not created (D2)' do
      criar(reenvio_quem: 'nao_leu', reenvio_dias: 3, reenvio_mensagem: { texto: 'Ainda aí?' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('reenvio_quem_invalido')
      expect(account.campaigns.count).to eq(0)
    end

    it 'creates the campaign without a second message when none is asked' do
      criar

      expect(response).to have_http_status(:ok)
      expect(Autonomia::CampanhaOpcoesDeEnvio.count).to eq(0)
    end
  end

  context 'when sending an e-mail campaign' do
    let(:identity) { create(:email_sender_identity, account: account, domain: 'empresa.com.br', from_email: 'ola@empresa.com.br') }
    let(:audience) do
      saved_audience(account: account, user: user, content: "Nome,Email\nAna,ana@alfa.com.br\n", mapping: { 'name' => 0, 'email' => 1 })
    end
    let(:campaign) do
      CampaignJourney::EmailCampaignCreator.new(
        account: account, campaign_import: audience,
        attributes: { title: 'Novidades', sender_identity_id: identity.id, from_email: 'ola@empresa.com.br' }
      ).perform
    end

    before do
      allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
      allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue)
    end

    def medir(params)
      put "/api/v1/accounts/#{account.id}/campaign_journey/email_medicoes/#{campaign.id}", params: params, headers: headers, as: :json
    end

    it 'saves the new subject, and turns it off when the review sends nothing' do
      medir({ reenvio_quem: 'nao_respondeu', reenvio_dias: 2, reenvio_mensagem: { assunto: 'Viu a novidade?' } })
      expect(response).to have_http_status(:no_content)
      expect(opcoes_de(campaign)).to have_attributes(reenvio_dias: 2, reenvio_mensagem: { 'assunto' => 'Viu a novidade?' })

      medir({})
      expect(opcoes_de(campaign).reenvio_quem).to be_nil
    end

    it 'refuses an empty subject' do
      medir({ reenvio_quem: 'nao_respondeu', reenvio_dias: 2, reenvio_mensagem: { assunto: ' ' } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'campaign_journey.invalid_reenvio', 'code' => 'reenvio_sem_assunto')
    end
  end
end
