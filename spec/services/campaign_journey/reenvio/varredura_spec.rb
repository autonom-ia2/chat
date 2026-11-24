require 'rails_helper'

# #3101 (§4.3, D1): a varredura do "Mandar de novo". Quando a primeira termina, grava a hora (último envio + dias); na
# hora, cria a campanha da segunda mensagem do mesmo canal só com quem recebeu e não respondeu (e não pediu para sair
# nem foi bloqueado), com o nome "<nome> · segunda mensagem", a mesma caixa e o melhor horário da primeira.
RSpec.describe CampaignJourney::Reenvio::Varredura, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:reply_inbox) { create_crm_inbox(account: account) }

  before { account.update!(locale: 'pt_BR') }

  def opcoes_de(campaign)
    Autonomia::CampanhaOpcoesDeEnvio.find_by(campanha: campaign)
  end

  def responder(contact, campaign)
    CampaignJourney::CampaignMarks.mark!(create_crm_conversation(account: account, inbox: reply_inbox, contact: contact), campaign)
  end

  def pessoa(nome)
    account.contacts.find_by!(name: nome)
  end

  context 'with SMS' do
    let!(:inbox) { journey_twilio_sms_inbox(account) }
    let!(:audience) do
      saved_audience(account: account, user: user, content: "Nome,Celular\nAna,11987654321\nBia,21987654321\nCaio,31987654321\n")
    end
    let!(:sent) { stub_twilio_sms }

    def primeira(reenvio = {})
      campaign = CampaignJourney::SmsCampaignCreator.new(
        account: account, campaign_import: audience, channel: 'sms',
        attributes: { title: 'Parcela', inbox_id: inbox.id, message: 'Oi {{contact.first_name}}, sua parcela vence amanhã' }
      ).perform
      CampaignJourney::Reenvio.guardar!(campaign, { reenvio_quem: 'nao_respondeu', reenvio_dias: 3,
                                                    reenvio_mensagem: { texto: 'Ainda aí, {{contact.first_name}}?' } }.merge(reenvio))
      campaign
    end

    def enviar(campaign)
      Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform
    end

    it 'waits for the first one to finish, then sends the second only to who did not reply, in a new campaign' do
      campaign = primeira
      Autonomia::MelhorHorario.guardar!(campaign, true)

      described_class.rodar
      expect(opcoes_de(campaign)).to have_attributes(reenvio_status: 'aguardando', reenvio_em: nil)

      enviar(campaign)
      responder(pessoa('Ana'), campaign)
      described_class.rodar
      ultimo = CampaignRecipient.where(campaign: campaign).maximum(:sent_at)
      expect(opcoes_de(campaign).reenvio_em).to be_within(1.second).of(ultimo + 3.days)
      expect(account.campaigns.count).to eq(1)

      travel 3.days + 1.minute do
        described_class.rodar
      end

      opcoes = opcoes_de(campaign)
      nova = account.campaigns.where.not(id: campaign.id).sole
      expect(opcoes).to have_attributes(reenvio_status: 'enviado', reenvio_campanha: nova)
      expect(nova).to have_attributes(title: 'Parcela · segunda mensagem', inbox_id: inbox.id, message: 'Ainda aí, {{contact.first_name}}?')
      publico = CampaignAudienceLink.for_campaign(nova).campaign_import
      expect(publico.options['source']).to eq('segunda_mensagem')
      expect(publico.campaign_import_rows.pluck(:contact_id)).to contain_exactly(pessoa('Bia').id, pessoa('Caio').id)
      expect(Autonomia::MelhorHorario.ligado?(nova)).to be(true)
      expect(opcoes_de(nova).reenvio_status).to be_nil

      enviar(nova)
      expect(sent.last(2).pluck('Body')).to contain_exactly('Ainda aí, Bia?', 'Ainda aí, Caio?')
    end

    it 'leaves out who refused messages or was blocked in the meantime' do
      campaign = primeira
      enviar(campaign)
      pessoa('Caio').update!(blocked: true)

      travel 3.days + 1.hour do
        described_class.rodar
      end

      nova = opcoes_de(campaign).reenvio_campanha
      expect(CampaignAudienceLink.for_campaign(nova).campaign_import.campaign_import_rows.pluck(:contact_id))
        .to contain_exactly(pessoa('Ana').id, pessoa('Bia').id)
    end

    it 'is sem_ninguem when everybody replied, and creates nothing' do
      campaign = primeira
      enviar(campaign)
      %w[Ana Bia Caio].each { |nome| responder(pessoa(nome), campaign) }

      travel 3.days + 1.hour do
        described_class.rodar
      end

      expect(opcoes_de(campaign).reenvio_status).to eq('sem_ninguem')
      expect(account.campaigns.count).to eq(1)
    end

    it 'is sem_ninguem when nobody got the first one' do
      campaign = primeira
      CampaignJourney::AudienceContacts.contacts_for(CampaignAudienceLink.for_campaign(campaign), channel: :sms).find_each do |contact|
        CampaignRecipient.create!(account: account, campaign: campaign, contact: contact, inbox: inbox, status: :skipped)
      end
      campaign.update!(campaign_status: :completed)

      described_class.rodar

      expect(opcoes_de(campaign)).to have_attributes(reenvio_status: 'sem_ninguem', reenvio_em: nil)
    end

    it 'cancels when the first one is edited before the second goes out' do
      campaign = primeira
      campaign.update!(message: 'Oi, outro texto')

      expect(opcoes_de(campaign).reenvio_status).to eq('cancelado')
    end

    it 'cancels, without error, when the first one no longer exists' do
      campaign = primeira
      campaign.destroy!

      expect { described_class.rodar }.not_to raise_error
      expect(Autonomia::CampanhaOpcoesDeEnvio.find_by(campanha_type: 'Campaign', campanha_id: campaign.id).reenvio_status).to eq('cancelado')
    end

    it 'never creates two campaigns when the sweep runs again' do
      campaign = primeira
      enviar(campaign)

      travel 3.days + 1.hour do
        2.times { described_class.rodar }
      end

      expect(account.campaigns.count).to eq(2)
    end
  end

  context 'with WhatsApp Oficial' do
    let(:lembrete) do
      { 'name' => 'lembrete', 'status' => 'APPROVED', 'category' => 'MARKETING', 'language' => 'pt_BR', 'namespace' => 'ns_lembrete',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, ainda quer renovar?' }] }
    end
    let(:channel) do
      journey_cloud_channel(account).tap do |canal|
        canal.update!(message_templates: [CampaignJourneyHelpers::JOURNEY_TEMPLATE, lembrete])
      end
    end
    let(:audience) do
      saved_audience(account: account, user: user, content: "Nome,Celular\nAna,11987654321\nBia,21987654321\n")
    end
    let(:primeira_ligacao) { { '1' => { 'source' => 'contact', 'value' => 'first_name' } } }

    def primeira(quem)
      campaign = CampaignJourney::WhatsappCampaignCreator.new(
        account: account, campaign_import: audience, channel: 'whatsapp_cloud',
        attributes: { title: 'Renovação', inbox_id: channel.inbox.id, template_params: journey_template_params,
                      variable_bindings: { '1' => { source: 'contact', value: 'first_name' }, '2' => { source: 'fixed', value: 'outubro' },
                                           '3' => { source: 'fixed', value: 'Equipe' } } }
      ).perform
      CampaignJourney::Reenvio.guardar!(campaign, reenvio_quem: quem, reenvio_dias: 1, reenvio_mensagem: {
                                          modelo_id: 'lembrete', ligacoes: primeira_ligacao,
                                          template_params: { name: 'lembrete', language: 'pt_BR', namespace: 'ns_lembrete',
                                                             category: 'MARKETING', processed_params: { body: { '1' => '' } } }
                                        })
      campaign
    end

    def recebeu(campaign, nome, **atributos)
      CampaignRecipient.create!(account: account, campaign: campaign, contact: pessoa(nome), inbox: channel.inbox,
                                sent_at: 2.hours.ago, **atributos)
    end

    it '"did not read" sends the other template only to who has not read the first one' do
      campaign = primeira('nao_leu')
      recebeu(campaign, 'Ana', status: :read, read_at: 1.hour.ago)
      recebeu(campaign, 'Bia', status: :delivered)
      campaign.update!(campaign_status: :completed)

      travel 1.day do
        described_class.rodar
      end

      nova = opcoes_de(campaign).reenvio_campanha
      expect(nova).to have_attributes(title: 'Renovação · segunda mensagem', inbox_id: channel.inbox.id)
      expect(nova.template_params).to include('name' => 'lembrete', 'language' => 'pt_BR')
      link = CampaignAudienceLink.for_campaign(nova)
      expect(link.variable_bindings).to eq(primeira_ligacao)
      expect(link.campaign_import.campaign_import_rows.pluck(:contact_id)).to eq([pessoa('Bia').id])
    end

    it '"did not reply" also sends to who read and did not reply' do
      campaign = primeira('nao_respondeu')
      recebeu(campaign, 'Ana', status: :read, read_at: 1.hour.ago)
      recebeu(campaign, 'Bia', status: :delivered)
      campaign.update!(campaign_status: :completed)

      travel 1.day do
        described_class.rodar
      end

      publico = CampaignAudienceLink.for_campaign(opcoes_de(campaign).reenvio_campanha).campaign_import
      expect(publico.campaign_import_rows.pluck(:contact_id)).to contain_exactly(pessoa('Ana').id, pessoa('Bia').id)
    end

    it 'is falhou when the template was taken out of the inbox, and leaves nothing behind' do
      campaign = primeira('nao_respondeu')
      recebeu(campaign, 'Bia', status: :delivered)
      campaign.update!(campaign_status: :completed)
      channel.update!(message_templates: [CampaignJourneyHelpers::JOURNEY_TEMPLATE])
      publicos = account.campaign_imports.count

      travel 1.day do
        described_class.rodar
      end

      expect(opcoes_de(campaign).reenvio_status).to eq('falhou')
      expect(account.campaigns.count).to eq(1)
      expect(account.campaign_imports.count).to eq(publicos)
    end
  end

  context 'with WhatsApp API' do
    let(:inbox) { create_whatsapp_api_inbox(account: account) }
    let(:audience) do
      saved_audience(account: account, user: user, content: "Nome,Celular\nAna,11987654321\nBia,21987654321\n")
    end

    around do |example|
      with_modified_env(WHATSAPP_API_CAMPAIGNS_ENABLED: 'true') { example.run }
    end

    before do
      allow(WhatsappApiCampaigns::Config).to receive(:enabled?).and_return(true)
      allow(WhatsappApiCampaigns::ScheduleDueCampaignsJob).to receive(:perform_later)
    end

    it 'creates the second campaign with the text, for who did not reply' do
      campaign = CampaignJourney::WhatsappApiCampaignCreator.new(
        account: account, user: user, campaign_import: audience,
        params: ActionController::Parameters.new(title: 'Vistoria', inbox_id: inbox.id, message_body: 'Oi {{contact.first_name}}')
      ).perform
      CampaignJourney::Reenvio.guardar!(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 2,
                                                  reenvio_mensagem: { texto: 'Ainda dá tempo, {{contact.first_name}}' })
      %w[Ana Bia].each do |nome|
        campaign.whatsapp_api_campaign_recipients.create!(account: account, inbox: inbox, contact: pessoa(nome), status: :sent,
                                                          sent_at: 1.hour.ago)
      end
      campaign.update!(status: :completed)
      responder(pessoa('Ana'), campaign)

      travel 2.days do
        described_class.rodar
      end

      nova = opcoes_de(campaign).reenvio_campanha
      expect(nova).to be_a(WhatsappApiCampaign)
      expect(nova).to have_attributes(title: 'Vistoria · segunda mensagem', inbox_id: inbox.id, created_by_id: user.id,
                                      message_body: 'Ainda dá tempo, {{contact.first_name}}')
      expect(CampaignAudienceLink.for_campaign(nova).campaign_import.campaign_import_rows.pluck(:contact_id)).to eq([pessoa('Bia').id])
    end

    it 'cancels when the first one is cancelled' do
      campaign = CampaignJourney::WhatsappApiCampaignCreator.new(
        account: account, user: user, campaign_import: audience,
        params: ActionController::Parameters.new(title: 'Vistoria', inbox_id: inbox.id, message_body: 'Oi')
      ).perform
      CampaignJourney::Reenvio.guardar!(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 2, reenvio_mensagem: { texto: 'De novo' })
      campaign.cancel!

      described_class.rodar

      expect(opcoes_de(campaign).reenvio_status).to eq('cancelado')
    end
  end

  context 'with e-mail' do
    let(:identity) { create(:email_sender_identity, account: account, domain: 'empresa.com.br', from_email: 'ola@empresa.com.br') }
    let(:audience) do
      saved_audience(account: account, user: user, content: "Nome,Email\nAna,ana@alfa.com.br\nBia,bia@alfa.com.br\n",
                     mapping: { 'name' => 0, 'email' => 1 })
    end

    around do |example|
      with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow', EMAIL_REPUTATION_PROVIDER_MONITOR: 'false',
                        EMAIL_REPUTATION_PROVIDER_BLOCK: 'false', EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') { example.run }
    end

    before do
      allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
      allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue)
    end

    it 'sends the same content with the new subject (D3), scheduled for the e-mail checks to run first' do
      campaign = CampaignJourney::EmailCampaignCreator.new(
        account: account, campaign_import: audience,
        attributes: { title: 'Novidades', sender_identity_id: identity.id, from_email: 'ola@empresa.com.br', from_name: 'Loja' }
      ).perform
      campaign.update!(subject: 'Chegou a coleção', body_html: '<p>Coleção nova</p>', body_mjml: '<mjml></mjml>')
      CampaignJourney::Reenvio.guardar!(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 3,
                                                  reenvio_mensagem: { assunto: 'Você viu a coleção?' })
      campaign.email_campaign_recipients.update_all(status: EmailCampaignRecipient.statuses[:delivered], sent_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
      campaign.update_columns(status: EmailCampaign.statuses[:sent]) # rubocop:disable Rails/SkipsModelValidations
      responder(pessoa('Ana'), campaign)

      travel 3.days do
        described_class.rodar

        nova = opcoes_de(campaign).reenvio_campanha
        expect(nova).to be_a(EmailCampaign)
        expect(nova).to have_attributes(name: 'Novidades · segunda mensagem', subject: 'Você viu a coleção?', body_html: '<p>Coleção nova</p>',
                                        sender_identity_id: identity.id, from_name: 'Loja', status: 'scheduled')
        expect(nova.scheduled_at).to be_within(1.minute).of(15.minutes.from_now)
        expect(nova.email_campaign_recipients.pluck(:contact_id)).to eq([pessoa('Bia').id])
      end
    end
  end
end
