require 'rails_helper'

# #2717: campanha de e-mail aberta (decisão do Rodrigo de 08/11). A lista segue o Público depois do primeiro envio:
# quem entra depois também recebe, uma vez, pela régua de sempre; quem sai antes do envio não recebe; a campanha não
# fecha sozinha. A fechada continua como hoje. Os jobs rodam de verdade (checagem de higiene e envio); só o provedor
# é dublê: nenhum e-mail sai.
RSpec.describe 'Campanha de e-mail aberta (#2717)', :aggregate_failures, type: :request do
  include ActiveJob::TestHelper

  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false',
                      EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:identity) { create(:email_sender_identity, account: account, domain: 'clinica.com.br', from_email: 'ola@clinica.com.br') }
  let(:audience) do
    saved_audience(account: account, user: user, mapping: { 'name' => 0, 'email' => 1 }, content: "Nome,Email\nAna Souza,ana@alfa.com.br\n")
  end
  let(:enviados) { [] }
  # Só a checagem de higiene e o envio rodam; o resto (avatar do contato etc.) fica na fila.
  let(:envio) { [EmailCampaigns::RecipientPreflightJob, EmailCampaigns::DeliveryJob] }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    stub_const('EmailCampaigns::DeliveryEngine::SEND_INTERVAL', 0.seconds)
    provedor = instance_double(EmailCampaigns::Ses::Sender)
    allow(provedor).to receive(:deliver) { |**mail| enviados << mail[:to] and "ses-#{enviados.size}" }
    allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(provedor)
  end

  def headers = { 'api_access_token' => user.access_token.token }

  def criar(aberta:)
    perform_enqueued_jobs(only: envio) do
      post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns",
           params: { campaign_import_id: audience.id, channel: 'email',
                     campaign: { title: 'Manutenção', delivery_mode: 'ses', sender_identity_id: identity.id,
                                 from_email: 'ola@clinica.com.br', aberta: aberta } },
           headers: headers, as: :json
    end
    campanha = EmailCampaign.find(response.parsed_body['id'])
    campanha.update!(subject: 'Hora da manutenção', body_html: '<p>Oi</p><a href="{{ unsubscribe_url }}">Sair</a>')
    campanha
  end

  def mandar(campanha)
    perform_enqueued_jobs(only: envio) do
      post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campanha.id}/send_now", headers: headers, as: :json
    end
    expect(response).to have_http_status(:ok)
  end

  # O que a Automação fará no PR-B: a pessoa entra no Público (linha com o e-mail atual dela) e a lista sincroniza.
  def entra_no_publico(campanha, nome, email, **contato_extra)
    contato = create(:contact, account: account, name: nome, email: email, **contato_extra)
    linha = CampaignImportRow.create!(campaign_import: audience, contact: contato, row_number: audience.campaign_import_rows.maximum(:row_number) + 1,
                                      status: :imported, normalized_email_hash: Digest::SHA256.hexdigest(email))
    perform_enqueued_jobs(only: envio) { CampaignJourney::CampanhaAberta.sincronizar!(campanha) }
    linha
  end

  it 'aberta: quem entra no Público depois do primeiro envio recebe, uma vez, e a campanha segue enviando' do
    campanha = criar(aberta: true)
    expect(response.parsed_body['aberta']).to be(true)

    mandar(campanha)
    expect(enviados).to eq(['ana@alfa.com.br'])
    expect(campanha.reload).to be_sending

    entra_no_publico(campanha, 'Bia Lima', 'bia@beta.com.br')
    expect(enviados).to eq(%w[ana@alfa.com.br bia@beta.com.br])
    expect(campanha.reload).to be_sending

    perform_enqueued_jobs(only: envio) { CampaignJourney::CampanhaAberta.sincronizar!(campanha) }
    expect(enviados).to eq(%w[ana@alfa.com.br bia@beta.com.br])
  end

  it 'aberta: quem descadastrou ou recusou mensagem não recebe ao entrar' do
    campanha = criar(aberta: true)
    mandar(campanha)
    EmailSuppression.create!(account: account, email: 'caio@gama.com.br', reason: 'unsubscribe', source: 'link')

    entra_no_publico(campanha, 'Caio Reis', 'caio@gama.com.br')
    entra_no_publico(campanha, 'Eva Rocha', 'eva@out.com.br', opted_out_at: Time.current)

    expect(enviados).to eq(['ana@alfa.com.br'])
    expect(campanha.email_campaign_recipients.find_by('lower(email) = ?', 'caio@gama.com.br')).to be_suppressed
    expect(campanha.email_campaign_recipients.find_by('lower(email) = ?', 'eva@out.com.br')).to be_nil
  end

  it 'aberta: quem sai do Público antes do envio não recebe' do
    campanha = criar(aberta: true)
    mandar(campanha)
    campanha.pause!

    linha = entra_no_publico(campanha, 'Dani Melo', 'dani@delta.com.br')
    expect(campanha.email_campaign_recipients.pluck(:email)).to include('dani@delta.com.br')
    linha.destroy!
    CampaignJourney::CampanhaAberta.sincronizar!(campanha)

    expect(campanha.email_campaign_recipients.pluck(:email)).not_to include('dani@delta.com.br')
    expect(enviados).to eq(['ana@alfa.com.br'])
  end

  it 'aberta: pode sair com a lista vazia e manda para quem entrar depois' do
    audience.campaign_import_rows.update_all(status: CampaignImportRow.statuses[:import_failed]) # rubocop:disable Rails/SkipsModelValidations
    campanha = criar(aberta: true)
    expect(campanha.email_campaign_recipients).to be_empty

    mandar(campanha)
    expect(campanha.reload).to be_sending

    entra_no_publico(campanha, 'Bia Lima', 'bia@beta.com.br')
    expect(enviados).to eq(['bia@beta.com.br'])
  end

  it 'fechada (como hoje): fecha em enviada, e quem entra depois não recebe' do
    campanha = criar(aberta: false)
    expect(response.parsed_body['aberta']).to be(false)

    mandar(campanha)
    expect(campanha.reload).to be_sent

    entra_no_publico(campanha, 'Bia Lima', 'bia@beta.com.br')
    perform_enqueued_jobs(only: envio) { CampaignJourney::EmailAudienceGate.sync!(campanha.reload) }

    expect(enviados).to eq(['ana@alfa.com.br'])
    expect(campanha.email_campaign_recipients.pluck(:email)).to eq(['ana@alfa.com.br'])
  end

  it 'aberta na régua "exigir": quem entra no meio é conferido antes e recebe, sem pausar a campanha' do
    conferido = { status: 'valid', reason_code: 'mx', valid_until: 1.hour.from_now }
    allow(EmailCampaigns::AddressPreflight).to receive(:new).and_return(instance_double(EmailCampaigns::AddressPreflight, call: conferido))

    with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'enforce') do
      campanha = criar(aberta: true)
      mandar(campanha)
      entra_no_publico(campanha, 'Bia Lima', 'bia@beta.com.br')

      expect(campanha.reload).to be_sending
      expect(campanha.hygiene_pause_reason).to be_nil
    end
    expect(enviados).to eq(%w[ana@alfa.com.br bia@beta.com.br])
  end

  it 'aberta: o motor deixa de fora quem ainda não foi conferido, e a conferência vencida não reabre passada' do
    campanha = criar(aberta: true)
    mandar(campanha)
    entra_no_publico(campanha, 'Bia Lima', 'bia@beta.com.br')
    nova = campanha.email_campaign_recipients.create!(email: 'caio@gama.com.br', status: :pending, preflight_status: 'unchecked')

    expect(CampaignJourney::CampanhaAberta.a_enviar(campanha)).not_to include(nova)

    nova.update!(preflight_status: 'valid', preflight_valid_until: 1.minute.ago)
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue)
    allow(EmailCampaigns::DeliveryJob).to receive(:perform_later)
    CampaignJourney::CampanhaAberta.depois_da_checagem(campanha)

    expect(EmailCampaigns::RecipientPreflightJob).not_to have_received(:enqueue)
    expect(EmailCampaigns::DeliveryJob).to have_received(:perform_later).with(campanha.id)
  end

  describe 'envio pela caixa (ritmo humano)' do
    let(:caixa) { create(:channel_email, account: account, email: 'clinica@clinica.com.br').inbox }
    let(:campanha) do
      created = CampaignJourney::EmailCampaignCreator.new(
        account: account, campaign_import: audience,
        attributes: { title: 'Manutenção', delivery_mode: 'direct_inbox', sender_inbox_id: caixa.id, aberta: true }
      ).perform
      created.update!(subject: 'Oi', body_html: '<p>Oi</p>', status: :sending)
      created
    end
    let(:motor) { EmailCampaigns::DirectInbox::DeliveryEngine }

    after { Redis::Alfred.delete(motor.chain_key(campanha.id)) }

    it 'com um tick já agendado, quem entra não abre outra cadeia' do
      Redis::Alfred.set(motor.chain_key(campanha.id), 'cadeia-viva', ex: 120)
      allow(EmailCampaigns::DeliveryJob).to receive(:perform_later)

      CampaignJourney::CampanhaAberta.acordar_envio(campanha)

      expect(EmailCampaigns::DeliveryJob).not_to have_received(:perform_later)
    end

    it 'tick de uma cadeia que já não é a última para sem enviar' do
      Redis::Alfred.set(motor.chain_key(campanha.id), 'a-ultima', ex: 120)
      engine = motor.new(campanha)
      allow(engine).to receive(:deliver_tick)

      engine.tick('cadeia-velha')
      expect(engine).not_to have_received(:deliver_tick)

      engine.tick('a-ultima')
      expect(engine).to have_received(:deliver_tick).once
      expect(motor.tick_scheduled?(campanha)).to be(false)
    end
  end
end
