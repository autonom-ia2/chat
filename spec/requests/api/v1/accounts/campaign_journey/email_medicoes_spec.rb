require 'rails_helper'

# #3098: "Quem comprou depois" do e-mail da jornada, gravado logo antes de agendar ou enviar. Sorteia o grupo, e a
# sincronização do público tira quem foi sorteado (o pendente sai; ninguém vira "Pulado").
RSpec.describe 'Campaign journey e-mail medição (#3098)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false',
                      EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:identity) { create(:email_sender_identity, account: account, domain: 'empresa.com.br', from_email: 'ola@empresa.com.br') }
  let(:content) do
    linhas = (0...10).map { |i| "Pessoa #{i},pessoa#{i}@alfa.com.br" }
    "Nome,Email\n#{linhas.join("\n")}\n"
  end
  let(:audience) { saved_audience(account: account, user: user, content: content, mapping: { 'name' => 0, 'email' => 1 }) }
  let(:campaign) do
    CampaignJourney::EmailCampaignCreator.new(
      account: account, campaign_import: audience,
      attributes: { title: 'Novidades', sender_identity_id: identity.id, from_email: 'ola@empresa.com.br' }
    ).perform
  end
  let(:link) { CampaignAudienceLink.for_campaign(campaign) }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue)
  end

  def medir(params, id: campaign.id)
    put "/api/v1/accounts/#{account.id}/campaign_journey/email_medicoes/#{id}",
        params: params, headers: { 'api_access_token' => user.access_token.token }, as: :json
  end

  it 'grava a janela e o grupo, sorteia, e a sincronização tira o grupo dos destinatários' do
    expect(campaign.email_campaign_recipients.count).to eq(10)

    medir({ janela_de_compra_dias: 15, grupo_de_controle_pct: 20 })

    expect(response).to have_http_status(:no_content)
    expect(link.reload).to have_attributes(janela_de_compra_dias: 15, grupo_de_controle_pct: 20)
    fora = link.campaign_control_contacts.pluck(:contact_id)
    expect(fora.size).to eq(2)

    CampaignJourney::EmailAudienceRecipients.new(campaign.reload).sync!
    expect(campaign.email_campaign_recipients.count).to eq(8)
    expect(campaign.email_campaign_recipients.where(contact_id: fora)).to be_empty
  end

  it 'quem tem e-mail suprimido não entra no sorteio e não sobra linha de quem foi sorteado' do
    suprimido = 'pessoa0@alfa.com.br'
    EmailSuppression.create!(account: account, email: suprimido, reason: 'hard_bounce')
    expect(campaign.email_campaign_recipients.detect { |recipient| recipient.email == suprimido }).to be_suppressed

    medir({ grupo_de_controle_pct: 20 })

    fora = link.reload.campaign_control_contacts.pluck(:contact_id)
    expect(fora.size).to eq(1)
    expect(fora).not_to include(account.contacts.from_email(suprimido)&.id)
    CampaignJourney::EmailAudienceRecipients.new(campaign.reload).sync!
    expect(campaign.email_campaign_recipients.where(contact_id: fora)).to be_empty
    expect(campaign.email_campaign_recipients.count).to eq(9)
  end

  it 'recusa depois do envio e valor fora das opções' do
    medir({ janela_de_compra_dias: 9 })
    expect(response).to have_http_status(:unprocessable_entity)

    campaign.update_columns(status: EmailCampaign.statuses.fetch('sent')) # rubocop:disable Rails/SkipsModelValidations
    medir({ janela_de_compra_dias: 15 })
    expect(response.parsed_body['error']).to eq('campaign_journey.already_sent')
  end

  it 'não acha campanha de outra conta' do
    outra = create(:account)
    medir({ janela_de_compra_dias: 15 }, id: create(:email_campaign, account: outra).id)

    expect(response).to have_http_status(:not_found)
  end

  # #3101: a revisão do e-mail grava o melhor horário junto da medição; sem a chave, desliga.
  it 'liga e desliga o melhor horário do e-mail' do
    medir({ grupo_de_controle_pct: 0, melhor_horario: true })
    expect(response).to have_http_status(:no_content)
    expect(Autonomia::MelhorHorario.ligado?(campaign)).to be(true)

    medir({ grupo_de_controle_pct: 0 })
    expect(Autonomia::MelhorHorario.ligado?(campaign)).to be(false)
  end
end
