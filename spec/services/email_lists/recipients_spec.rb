require 'rails_helper'

# G52 (#2760): a campanha de e-mail com lista vai para quem está na lista na hora do envio. Molde: o público salvo
# (CampaignJourney::EmailAudienceGate).
RSpec.describe EmailLists::Recipients, :aggregate_failures do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow',
                      EMAIL_REPUTATION_MODE: 'shadow', EMAIL_REPUTATION_PROVIDER_MONITOR: 'false',
                      EMAIL_REPUTATION_PROVIDER_BLOCK: 'false', EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') { example.run }
  end

  let(:account) { create(:account) }
  let(:lista) { EmailList.criar(account: account, name: 'Dicas do mês') }
  let(:campanha) { create(:email_campaign, account: account) }

  before { allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue) }

  def na_lista(email, name: 'Ana Souza', **atributos)
    create(:contact, account: account, email: email, name: name, **atributos).tap { |contato| contato.update_labels([lista.label.title]) }
  end

  def emails = campanha.email_campaign_recipients.order(:email).pluck(:email)

  describe 'ao escolher a lista no rascunho' do
    it 'monta os destinatários com quem pode receber: com e-mail, sem recusa; descadastrado entra como suppressed' do
      ana = na_lista('Ana@Exemplo.com', name: 'Ana Souza')
      na_lista(nil, phone_number: '+5511988887777')
      na_lista('bia@exemplo.com').opt_out!(source: 'manual')
      na_lista('caio@exemplo.com')
      EmailSuppression.create!(account: account, email: 'caio@exemplo.com', reason: 'unsubscribe')
      create(:contact, account: account, email: 'fora@exemplo.com')

      campanha.update!(email_list: lista)

      recipients = campanha.email_campaign_recipients.order(:email)
      expect(recipients.map { |r| [r.email, r.status] }).to eq([%w[ana@exemplo.com pending], %w[caio@exemplo.com suppressed]])
      expect(recipients.first).to have_attributes(contact_id: ana.id, name: 'Ana Souza')
      expect(recipients.first.custom_data).to include('primeiro_nome' => 'Ana')
      expect(campanha.reload.recipients_count).to eq(2)
      expect(EmailCampaigns::RecipientPreflightJob).to have_received(:enqueue).with(campanha.id)
    end

    it 'trocar para a planilha tira os pendentes da lista, para nunca misturar' do
      na_lista('ana@exemplo.com')
      campanha.update!(email_list: lista)

      campanha.update!(email_list: nil)

      expect(emails).to be_empty
    end

    it 'recusa lista de outra conta, campanha de público salvo e importação de planilha em andamento' do
      outra = EmailList.criar(account: create(:account), name: 'Outra')
      campanha.email_list = outra
      expect(campanha).not_to be_valid
      expect(campanha.errors[:email_list_id]).to include('must belong to the same account')

      allow(CampaignAudienceLink).to receive(:for_campaign).and_return(instance_double(CampaignAudienceLink))
      campanha.email_list = lista
      expect(campanha).not_to be_valid
      expect(campanha.errors[:email_list_id]).to include('audience_linked')
    end
  end

  describe 'na hora do envio' do
    before do
      na_lista('ana@exemplo.com')
      campanha.update!(email_list: lista)
    end

    it 'mandar agora põe quem entrou e tira o pendente que saiu, antes de conferir' do
      saiu = account.contacts.from_email('ana@exemplo.com')
      saiu.update_labels([])
      na_lista('bia@exemplo.com')

      expect(campanha.claim_for_sending!).to be(true)
      expect(emails).to eq(%w[bia@exemplo.com])
    end

    it 'agendar monta a lista de novo' do
      na_lista('bia@exemplo.com')

      expect(campanha.schedule!(scheduled_at: 1.day.from_now)).to be_truthy
      expect(emails).to eq(%w[ana@exemplo.com bia@exemplo.com])
    end

    it 'nunca mexe em destinatário mandado: depois do primeiro envio, a lista não muda mais' do
      campanha.email_campaign_recipients.first.update!(status: :sent, sent_at: Time.current)
      account.contacts.from_email('ana@exemplo.com').update_labels([])
      na_lista('bia@exemplo.com')

      expect(described_class.new(campanha).sync!).to eq(added: 0, removed: 0)
      expect(emails).to eq(%w[ana@exemplo.com])
    end

    it 'campanha sem destinatário ainda pode sair se a lista tem alguém (a conferência antes da montagem)' do
      vazia = create(:email_campaign, account: account, sender_identity: campanha.sender_identity)
      vazia.update!(email_list: EmailList.criar(account: account, name: 'Vazia'))
      expect(vazia.sendable?).to be(false)

      contato = create(:contact, account: account, email: 'dani@exemplo.com')
      contato.update_labels([vazia.email_list.label.title])
      expect(vazia.reload.sendable?).to be(true)
      expect(EmailCampaigns::Presentation::SendReadiness.new(vazia).call[:checks][:recipients]).to be(true)
      expect(vazia.claim_for_sending!).to be(true)
      expect(vazia.email_campaign_recipients.pluck(:email)).to eq(%w[dani@exemplo.com])
    end

    it 'o agendador espera o próximo ciclo quando entrou alguém, e manda no seguinte' do
      campanha.update!(status: :scheduled, scheduled_at: 1.minute.ago)
      na_lista('bia@exemplo.com')

      EmailCampaigns::Scheduler.new.perform
      expect(campanha.reload).to be_scheduled
      expect(emails).to eq(%w[ana@exemplo.com bia@exemplo.com])

      EmailCampaigns::Scheduler.new.perform
      expect(campanha.reload).to be_sending
    end

    it 'com a higiene em enforce, o agendador espera enquanto há pendente sem checagem' do
      campanha.update!(status: :scheduled, scheduled_at: 1.minute.ago)

      with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'enforce') { EmailCampaigns::Scheduler.new.perform }

      expect(campanha.reload).to be_scheduled
    end
  end

  describe 'quando a lista sai' do
    before do
      na_lista('ana@exemplo.com')
      campanha.update!(email_list: lista)
    end

    it 'apagar a lista tira do rascunho os pendentes dela' do
      lista.destroy!

      expect(campanha.reload.email_list_id).to be_nil
      expect(emails).to be_empty
      expect(campanha.recipients_count).to eq(0)
    end

    it 'apagar a etiqueta apaga a lista e tira do rascunho os pendentes dela' do
      lista.label.destroy!

      expect(EmailList.exists?(lista.id)).to be(false)
      expect(campanha.reload.email_list_id).to be_nil
      expect(emails).to be_empty
    end
  end

  describe 'quem só tem endereço bloqueado' do
    it 'não conta como alguém que recebe: a campanha não sai com zero envios' do
      vazia = create(:email_campaign, account: account, sender_identity: campanha.sender_identity)
      vazia.update!(email_list: EmailList.criar(account: account, name: 'Só bloqueados'))
      contato = create(:contact, account: account, email: 'eva@exemplo.com')
      EmailSuppression.create!(account: account, email: 'eva@exemplo.com', reason: 'hard_bounce')
      contato.update_labels([vazia.email_list.label.title])

      expect(described_class.new(vazia.reload).candidatos?).to be(false)
      expect(vazia.sendable?).to be(false)
      expect(EmailCampaigns::Presentation::SendReadiness.new(vazia).call[:checks][:recipients]).to be(false)
      expect(vazia.claim_for_sending!).to be(false)
      expect(vazia.reload).to be_draft
    end
  end

  describe 'a troca de lista e o estado da campanha' do
    before do
      na_lista('ana@exemplo.com')
      campanha.update!(email_list: lista)
    end

    it 'relê o estado sob a trava: a campanha que já saiu em outro processo não perde os destinatários' do
      velha = EmailCampaign.find(campanha.id)
      EmailCampaign.where(id: campanha.id).update_all(status: EmailCampaign.statuses[:sending]) # rubocop:disable Rails/SkipsModelValidations

      velha.update!(email_list: nil)

      expect(emails).to eq(%w[ana@exemplo.com])
    end

    it 'não monta de novo depois de qualquer histórico de envio, mesmo sem sent_at' do
      campanha.email_campaign_recipients.first.update!(status: :failed)
      na_lista('bia@exemplo.com')

      expect(described_class.new(campanha).sync!).to eq(added: 0, removed: 0)
      expect(emails).to eq(%w[ana@exemplo.com])
    end

    it 'guarda a empresa do contato no destinatário' do
      na_lista('bia@exemplo.com', name: 'Bia Lima', additional_attributes: { 'company_name' => 'Padaria Sol' })

      described_class.new(campanha).sync!

      bia = campanha.email_campaign_recipients.where(email: 'bia@exemplo.com').sole
      expect(bia.custom_data).to eq('primeiro_nome' => 'Bia', 'empresa' => 'Padaria Sol')
    end
  end

  describe 'o agendador quando a montagem quebra' do
    it 'marca a campanha como falha com o erro limpo, em vez de esperar para sempre' do
      na_lista('ana@exemplo.com')
      campanha.update!(email_list: lista)
      campanha.update!(status: :scheduled, scheduled_at: 1.minute.ago)
      allow(EmailLists::Gate).to receive(:sync!).and_raise(StandardError, 'quebrou')

      EmailCampaigns::Scheduler.new.perform

      expect(campanha.reload).to be_failed
      expect(campanha.last_error).to eq('quebrou')
    end
  end

  describe 'público salvo e lista nunca juntos' do
    it 'recusa ligar público salvo à campanha que já tem lista' do
      campanha.update!(email_list: lista)

      link = CampaignAudienceLink.new(account: account, campaign: campanha)

      expect(link).not_to be_valid
      expect(link.errors[:campaign]).to include('email_list_linked')
    end

    it 'aceita o público salvo na campanha sem lista' do
      expect(CampaignAudienceLink.new(account: account, campaign: campanha)).to be_valid
    end
  end
end
