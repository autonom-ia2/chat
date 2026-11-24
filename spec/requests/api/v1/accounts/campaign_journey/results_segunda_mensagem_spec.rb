require 'rails_helper'

# #3101 — o resultado da primeira campanha diz o que houve com a segunda mensagem do "Mandar de novo": aguardando (com a
# data prevista quando já se sabe), sem_ninguem, cancelado, falhou, ou enviado com a campanha nova, quantos receberam e
# quantos responderam (a mesma régua do resultado: a marca da campanha).
RSpec.describe 'Campaign journey results API — segunda mensagem (#3101)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:reply_inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:sms_inbox) { create(:channel_sms, account: account).inbox }
  let(:ana) { account.contacts.create!(name: 'Ana', phone_number: '+5511987654321', email: 'ana@alfa.com.br') }
  let(:bia) { account.contacts.create!(name: 'Bia', phone_number: '+5521987654322', email: 'bia@beta.com.br') }
  let(:caio) { account.contacts.create!(name: 'Caio', phone_number: '+5531987654323', email: 'caio@gama.com.br') }

  def headers
    { 'api_access_token' => admin.access_token.token }
  end

  def segunda_mensagem(channel, id)
    get "/api/v1/accounts/#{account.id}/campaign_journey/results/#{channel}/#{id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body.dig('payload', 'segunda_mensagem')
  end

  def reenvio!(campanha, status, **atributos)
    Autonomia::CampanhaOpcoesDeEnvio.create!(account: account, campanha: campanha, reenvio_quem: 'nao_respondeu', reenvio_dias: 3,
                                             reenvio_mensagem: { 'texto' => 'Ainda aí?' }, reenvio_status: status, **atributos)
  end

  def replied!(contact, campaign)
    CampaignJourney::CampaignMarks.mark!(create_crm_conversation(account: account, inbox: reply_inbox, contact: contact), campaign)
  end

  def campanha_oficial(titulo)
    create(:campaign, account: account, inbox: whatsapp_inbox, title: titulo, campaign_type: :one_off, template_params: { 'name' => 'oferta' })
  end

  def recebeu(campaign, contact, status)
    CampaignRecipient.create!(account: account, campaign: campaign, contact: contact, inbox: campaign.inbox, status: status,
                              sent_at: (1.hour.ago unless status == :failed))
  end

  describe 'WhatsApp Oficial' do
    let(:primeira) { campanha_oficial('Oferta') }

    it 'is nil when the campaign has no second message, or the option is off' do
      expect(segunda_mensagem('whatsapp_official', primeira.display_id)).to be_nil

      Autonomia::CampanhaOpcoesDeEnvio.create!(account: account, campanha: primeira, melhor_horario: true)
      expect(segunda_mensagem('whatsapp_official', primeira.display_id)).to be_nil
    end

    it 'is aguardando without a date until the first one finishes, then with the date it goes out' do
      opcoes = reenvio!(primeira, 'aguardando')
      expect(segunda_mensagem('whatsapp_official', primeira.display_id))
        .to eq('status' => 'aguardando', 'dias' => 3, 'quem' => 'nao_respondeu', 'previsto_em' => nil, 'campanha' => nil)

      quando = 3.days.from_now
      opcoes.update!(reenvio_em: quando)
      expect(segunda_mensagem('whatsapp_official', primeira.display_id)['previsto_em']).to eq(quando.to_i)
    end

    it 'shows who got and who replied to the second campaign, counted like its own result' do
      nova = campanha_oficial('Oferta · segunda mensagem')
      recebeu(nova, ana, :read)
      recebeu(nova, bia, :delivered)
      recebeu(nova, caio, :failed)
      replied!(ana, nova)
      replied!(bia, primeira) # respondeu à primeira, não à segunda: não conta aqui
      reenvio!(primeira, 'enviado', reenvio_em: 1.hour.ago, reenvio_campanha: nova)

      expect(segunda_mensagem('whatsapp_official', primeira.display_id)['campanha'])
        .to eq('channel' => 'whatsapp_official', 'id' => nova.display_id, 'name' => 'Oferta · segunda mensagem', 'processing' => false,
               'receberam' => 2, 'responderam' => 1)
    end

    it 'keeps enviado without the campaign when the second campaign was deleted' do
      nova = campanha_oficial('Oferta · segunda mensagem')
      reenvio!(primeira, 'enviado', reenvio_campanha: nova)
      nova.destroy!

      expect(segunda_mensagem('whatsapp_official', primeira.display_id)).to include('status' => 'enviado', 'campanha' => nil)
    end

    it 'never shows a campaign of another account as the second message' do
      outra_conta = create(:account)
      outra_caixa = create(:channel_whatsapp, account: outra_conta, sync_templates: false, validate_provider_config: false).inbox
      alheia = create(:campaign, account: outra_conta, inbox: outra_caixa, title: 'Alheia', campaign_type: :one_off)
      reenvio!(primeira, 'enviado', reenvio_campanha: alheia)

      expect(segunda_mensagem('whatsapp_official', primeira.display_id)).to include('status' => 'enviado', 'campanha' => nil)
    end

    it 'tells sem_ninguem, cancelado and falhou apart, with no campaign' do
      %w[sem_ninguem cancelado falhou].each do |status|
        campanha = campanha_oficial("Oferta #{status}")
        reenvio!(campanha, status)

        expect(segunda_mensagem('whatsapp_official', campanha.display_id)).to include('status' => status, 'campanha' => nil)
      end
    end
  end

  describe 'SMS' do
    it 'links the second SMS campaign under the sms result' do
      primeira = create(:campaign, account: account, inbox: sms_inbox, title: 'Parcela', campaign_type: :one_off)
      nova = create(:campaign, account: account, inbox: sms_inbox, title: 'Parcela · segunda mensagem', campaign_type: :one_off)
      recebeu(nova, ana, :delivered)
      replied!(ana, nova)
      reenvio!(primeira, 'enviado', reenvio_campanha: nova)

      expect(segunda_mensagem('sms', primeira.display_id)['campanha'])
        .to include('channel' => 'sms', 'id' => nova.display_id, 'receberam' => 1, 'responderam' => 1)
    end
  end

  describe 'WhatsApp API' do
    let(:api_inbox) { create_crm_whatsapp_api_inbox(account: account) }

    def campanha_api(titulo, status)
      WhatsappApiCampaign.create!(account: account, inbox: api_inbox, created_by: admin, title: titulo, audience: [{ 'type' => 'Label', 'id' => 1 }],
                                  message_body: 'Olá', scheduled_at: 1.hour.ago, status: status)
    end

    it 'counts sent people and marks the second campaign as still going out' do
      primeira = campanha_api('Vistoria', :completed)
      nova = campanha_api('Vistoria · segunda mensagem', :running)
      nova.whatsapp_api_campaign_recipients.create!(account: account, inbox: api_inbox, contact: ana, status: :sent, sent_at: 1.minute.ago)
      nova.whatsapp_api_campaign_recipients.create!(account: account, inbox: api_inbox, contact: bia, status: :pending)
      reenvio!(primeira, 'enviado', reenvio_campanha: nova)

      expect(segunda_mensagem('whatsapp_api', primeira.id)['campanha'])
        .to include('channel' => 'whatsapp_api', 'id' => nova.id, 'processing' => true, 'receberam' => 1, 'responderam' => 0)
    end
  end

  describe 'E-mail' do
    it 'counts delivered e-mails as received' do
      primeira = create(:email_campaign, account: account, name: 'Novidades', status: :sent)
      nova = create(:email_campaign, account: account, name: 'Novidades · segunda mensagem', status: :sent)
      create(:email_campaign_recipient, email_campaign: nova, email: 'ana@alfa.com.br', name: 'Ana', contact: ana, status: :delivered,
                                        sent_at: 1.hour.ago)
      create(:email_campaign_recipient, email_campaign: nova, email: 'bia@beta.com.br', name: 'Bia', status: :bounced, sent_at: 1.hour.ago)
      replied!(ana, nova)
      reenvio!(primeira, 'enviado', reenvio_campanha: nova)

      expect(segunda_mensagem('email', primeira.id)['campanha'])
        .to eq('channel' => 'email', 'id' => nova.id, 'name' => 'Novidades · segunda mensagem', 'processing' => false,
               'receberam' => 1, 'responderam' => 1)
    end
  end
end
