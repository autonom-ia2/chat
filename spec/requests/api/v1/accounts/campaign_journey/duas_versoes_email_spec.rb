require 'rails_helper'

# #3099 (D2): no e-mail, a versão 2 muda só o assunto. Gravada logo antes de enviar (PUT email_medicoes); o motor manda
# cada assunto para a sua versão, e o resto da lista espera a escolha.
RSpec.describe 'Campaign journey duas versões no e-mail (#3099)', :aggregate_failures, type: :request do
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
      attributes: { title: 'Novidades', sender_identity_id: identity.id, from_email: 'ola@empresa.com.br', subject: 'Oferta da semana' }
    ).perform
  end
  let(:link) { CampaignAudienceLink.for_campaign(campaign) }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue)
    stub_const('CampaignJourney::DuasVersoes::MINIMO_POR_VERSAO', 2)
    stub_const('CampaignJourney::DuasVersoes::MINIMO_NO_RESTO', 2)
  end

  def medir(params)
    put "/api/v1/accounts/#{account.id}/campaign_journey/email_medicoes/#{campaign.id}",
        params: params, headers: { 'api_access_token' => user.access_token.token }, as: :json
  end

  def duas_versoes(assunto = '{{nome}}, só hoje')
    { criterio: 'respostas', segunda: { subject: assunto } }
  end

  it 'sorteia o teste; só ele sai agora, cada um com o assunto da sua versão' do
    medir({ duas_versoes: duas_versoes })

    expect(response).to have_http_status(:no_content)
    expect(link.reload).to have_attributes(teste_estado: 'testando', teste_resto: 6, segunda_versao: { 'subject' => '{{nome}}, só hoje' })
    na_vez = EmailCampaigns::RitmoDoDestinatario.pendentes_na_vez(campaign.reload)
    expect(na_vez.pluck(:contact_id)).to match_array(link.campaign_version_contacts.pluck(:contact_id))

    motor = EmailCampaigns::DeliveryEngine.new(campaign)
    assuntos = na_vez.to_a.to_h do |recipient|
      [CampaignJourney::DuasVersoes.new(link).versao_de(recipient.contact_id), motor.send(:render, recipient)[:subject]]
    end
    expect(assuntos[1]).to eq('Oferta da semana')
    expect(assuntos[2]).to end_with(', só hoje')
    expect(assuntos[2]).to start_with('Pessoa')
  end

  it 'escolhida a versão, o resto entra na fila com o assunto dela' do
    medir({ duas_versoes: duas_versoes })
    campaign.update_columns(status: EmailCampaign.statuses.fetch('sending')) # rubocop:disable Rails/SkipsModelValidations

    CampaignJourney::DuasVersoes.new(link.reload).mandar_resto!(2, por: :voce)

    na_vez = EmailCampaigns::RitmoDoDestinatario.pendentes_na_vez(campaign.reload)
    expect(na_vez.count).to eq(10)
    expect(link.reload.campaign_version_contacts.where(fase: 'resto', versao: 2).count).to eq(6)
    expect { CampaignJourney::EnviarRestoJob.perform_now(link.id) }.to have_enqueued_job(EmailCampaigns::DeliveryJob).with(campaign.id)
  end

  it 'recusa o assunto da versão 2 igual ao da 1; sem a chave, a campanha fica sem duas versões' do
    medir({ duas_versoes: duas_versoes('Oferta da semana') })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('segunda_versao_igual')

    medir({ duas_versoes: duas_versoes })
    medir({ janela_de_compra_dias: 15 })
    expect(link.reload).to have_attributes(teste_criterio: nil, teste_estado: nil)
    expect(link.campaign_version_contacts).to be_empty
  end
end
