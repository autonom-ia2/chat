require 'rails_helper'

# #3099: o resto do público sai pelo caminho de cada canal depois da escolha. Cada ramo: campanha do Chatwoot (antes de
# sair, saindo, parada, com a retomada dos adiados rodando, terminada), WhatsApp API (agendada, terminada, com a
# corrente viva e com a corrente parada) e e-mail.
RSpec.describe CampaignJourney::DuasVersoes::EnvioDoResto, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }

  describe 'campanha do Chatwoot (SMS)' do
    let!(:inbox) { journey_twilio_sms_inbox(account) }
    let(:content) do
      linhas = (0...10).map { |i| "Pessoa #{i},1198765#{format('%04d', i)}" }
      "Nome,Celular\n#{linhas.join("\n")}\n"
    end
    let!(:audience) { saved_audience(account: account, user: user, content: content) }
    let!(:sent) { stub_twilio_sms }
    let(:campaign) do
      CampaignJourney::SmsCampaignCreator.new(
        account: account, campaign_import: audience, channel: 'sms',
        attributes: { title: 'Parcela', inbox_id: inbox.id, message: 'Oi, versão 1',
                      duas_versoes: { criterio: 'respostas', segunda: { message_body: 'Oi, versão 2' } } }
      ).perform
    end
    let(:link) { CampaignAudienceLink.for_campaign(campaign) }

    before do
      stub_const('CampaignJourney::DuasVersoes::MINIMO_POR_VERSAO', 2)
      stub_const('CampaignJourney::DuasVersoes::MINIMO_NO_RESTO', 2)
    end

    # A escolha enfileira o próprio EnviarRestoJob; a fila é limpa para olhar só o que o envio do resto fez.
    def escolher_e_enviar
      CampaignJourney::DuasVersoes.new(link).mandar_resto!(2, por: :voce, user: user)
      clear_enqueued_jobs
      described_class.new(link.reload).enviar!
    end

    it 'escolhida antes de a campanha sair, não manda nada: o disparo normal manda todo mundo' do
      escolher_e_enviar

      expect(sent).to be_empty
      expect(CampaignJourney::EnviarRestoJob).not_to have_been_enqueued
    end

    it 'com o teste ainda saindo, tenta de novo depois' do
      Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform
      campaign.update!(campaign_status: :processing)

      freeze_time do
        escolher_e_enviar
        expect(CampaignJourney::EnviarRestoJob).to have_been_enqueued.with(link.id).at(described_class::ESPERA_SE_PARADA.from_now)
      end
      expect(sent.size).to eq(4)
    end

    it 'com a campanha parada, tenta de novo depois' do
      Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform
      CampaignPause.create!(account: account, pausable: campaign, source: 'manual', reason_code: 'manual_pause', paused_at: Time.current)

      freeze_time do
        escolher_e_enviar
        expect(CampaignJourney::EnviarRestoJob).to have_been_enqueued.with(link.id).at(described_class::ESPERA_SE_PARADA.from_now)
      end
      expect(sent.size).to eq(4)
    end

    it 'com a retomada dos adiados rodando na mesma campanha, não manda junto e tenta de novo' do
      Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform
      allow(CampaignJourney::EnvioSozinho).to receive(:sozinho).and_return(false)

      freeze_time do
        escolher_e_enviar
        expect(CampaignJourney::EnviarRestoJob).to have_been_enqueued.with(link.id).at(described_class::ESPERA_SE_OCUPADA.from_now)
      end
      expect(sent.size).to eq(4)
    end

    it 'terminado o teste, manda o resto com a versão escolhida, dentro da trava da campanha' do
      Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform
      allow(CampaignJourney::EnvioSozinho).to receive(:sozinho).and_call_original

      escolher_e_enviar

      expect(CampaignJourney::EnvioSozinho).to have_received(:sozinho).with(campaign)
      expect(sent.size).to eq(10)
      expect(sent.last(6).pluck('Body')).to all(eq('Oi, versão 2'))
      expect(CampaignJourney::EnviarRestoJob).not_to have_been_enqueued
    end
  end

  describe 'campanha da WhatsApp API' do
    let(:inbox) { create_whatsapp_api_inbox(account: account) }
    let(:label) { account.labels.create!(title: "clientes_#{SecureRandom.hex(3)}") }
    let(:campaign) { create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label) }
    let(:link) { instance_double(CampaignAudienceLink, id: 42, campaign: campaign) }

    # O teste já foi resolvido (um destinatário); depois da escolha, entra uma pessoa nova no público: o resto.
    def com_teste(status:, destinatario: :sent, adiado_ate: nil)
      create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
      WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
      campaign.whatsapp_api_campaign_recipients.find_each do |recipient|
        recipient.update!(status: destinatario, adiado_ate: adiado_ate)
      end
      campaign.update!(status: status)
      create_labelled_contact(account: account, label: label, name: 'Bia Souza', phone_number: '+5521987654321')
    end

    def pendentes = campaign.whatsapp_api_campaign_recipients.pending.count

    it 'agendada, não mexe: o agendamento resolve o público inteiro na hora de sair' do
      campaign.update!(scheduled_at: 1.day.from_now)
      create_labelled_contact(account: account, label: label, name: 'Bia Souza', phone_number: '+5521987654321')

      expect { described_class.new(link).enviar! }.not_to have_enqueued_job(WhatsappApiCampaigns::DeliveryJob)
      expect(campaign.whatsapp_api_campaign_recipients.count).to eq(0)
    end

    it 'terminada, cria o resto, volta a andar e recomeça a corrente' do
      com_teste(status: :completed)

      expect { described_class.new(link).enviar! }.to have_enqueued_job(WhatsappApiCampaigns::DeliveryJob).with(campaign.id).once
      expect(campaign.reload).to be_running
      expect(pendentes).to eq(1)
    end

    it 'com a corrente viva (alguém pendente para agora), só cria o resto: a corrente pega sozinha' do
      com_teste(status: :running, destinatario: :pending)

      expect { described_class.new(link).enviar! }.not_to have_enqueued_job(WhatsappApiCampaigns::DeliveryJob)
      expect(pendentes).to eq(2)
    end

    it 'com a corrente parada (só adiados esperando), cria o resto e recomeça a corrente' do
      com_teste(status: :running, destinatario: :pending, adiado_ate: 2.hours.from_now)

      expect { described_class.new(link).enviar! }.to have_enqueued_job(WhatsappApiCampaigns::DeliveryJob).with(campaign.id).once
      expect(campaign.reload).to be_running
      expect(pendentes).to eq(2)
    end

    it 'pausada, só cria o resto: retomar a campanha recomeça a corrente' do
      com_teste(status: :paused, destinatario: :pending, adiado_ate: 2.hours.from_now)

      expect { described_class.new(link).enviar! }.not_to have_enqueued_job(WhatsappApiCampaigns::DeliveryJob)
      expect(pendentes).to eq(2)
    end

    it 'rodar de novo não cria o resto duas vezes nem uma segunda corrente' do
      com_teste(status: :completed)
      described_class.new(link).enviar!

      expect { described_class.new(link).enviar! }.not_to have_enqueued_job(WhatsappApiCampaigns::DeliveryJob)
      expect(campaign.whatsapp_api_campaign_recipients.count).to eq(2)
    end
  end

  describe 'campanha de e-mail' do
    let(:campaign) { create(:email_campaign, account: account) }
    let(:link) { instance_double(CampaignAudienceLink, id: 43, campaign: campaign) }

    it 'enviando, o motor volta a andar; fora disso, não' do
      campaign.update_columns(status: EmailCampaign.statuses[:sending]) # rubocop:disable Rails/SkipsModelValidations
      expect { described_class.new(link).enviar! }.to have_enqueued_job(EmailCampaigns::DeliveryJob).with(campaign.id)

      campaign.update_columns(status: EmailCampaign.statuses[:draft]) # rubocop:disable Rails/SkipsModelValidations
      expect { described_class.new(link).enviar! }.not_to have_enqueued_job(EmailCampaigns::DeliveryJob)
    end
  end
end
