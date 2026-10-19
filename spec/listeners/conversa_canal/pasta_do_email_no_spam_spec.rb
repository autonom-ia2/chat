require 'rails_helper'

# #1809, opção (b) do Rodrigo (18/10): a conversa de e-mail posta no Spam resolve sem mandar a pesquisa de satisfação,
# sem chamar o robô da caixa e sem rodar automações. A Lixeira resolve como o Resolver de sempre, e o "Não é spam"
# reabre com tudo normal. Os listeners rodam pelo dispatcher de verdade: o do robô no commit, os outros no job.
RSpec.describe ConversaCanal::PastaDoEmail do
  describe '.no_spam? nos listeners da pesquisa, do robô e das automações' do
    include ActiveJob::TestHelper

    let(:account) { create(:account) }
    let(:inbox) { create(:channel_email, account: account).inbox }
    let(:user) { create(:user, account: account, role: :administrator) }
    let(:contato) { create(:contact, account: account, email: 'oferta@exemplo.com') }
    let(:robo) { create(:agent_bot, account: account, outgoing_url: 'https://robo.exemplo.com/webhook') }
    let!(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contato) }
    let(:pesquisa) { instance_double(CsatSurveyService, perform: nil) }
    let(:automacao) { instance_double(AutomationRules::ActionService, perform: nil) }

    before do
      account.enable_features!('conversa_email_nova')
      inbox.update!(csat_survey_enabled: true)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: robo)
      create(:automation_rule, account: account, event_name: 'conversation_resolved', active: true, conditions: [], actions: [])
      create(:automation_rule, account: account, event_name: 'conversation_opened', active: true, conditions: [], actions: [])
      allow(CsatSurveyService).to receive(:new).and_return(pesquisa)
      allow(AutomationRules::ActionService).to receive(:new).and_return(automacao)
      allow(AutomationRules::ConditionsFilterService).to receive(:new).and_return(instance_double(AutomationRules::ConditionsFilterService,
                                                                                                  perform: true))
      Current.account = account
      clear_enqueued_jobs
    end

    after { Current.reset }

    def mover(pasta)
      perform_enqueued_jobs(only: EventDispatcherJob) do
        ConversaCanal::MoverParaPasta.new(conversation: conversa, pasta: pasta, user: user).perform
      end
    end

    def eventos_do_robo
      enqueued_jobs.select { |job| job['job_class'] == 'AgentBots::WebhookJob' }.map { |job| job['arguments'][1]['event'] }
    end

    it 'Spam: resolve sem pesquisa de satisfação, sem o robô da caixa e sem automação' do
      mover('spam')

      expect(conversa.reload).to be_resolved
      expect(pesquisa).not_to have_received(:perform)
      expect(eventos_do_robo).to be_empty
      expect(automacao).not_to have_received(:perform)
    end

    it 'Spam automático (remetente no Spam escreve numa conversa da Entrada): também sem os três' do
      ConversaCanal::RemetenteNoSpam.create!(account: account, inbox: inbox, email: 'oferta@exemplo.com')

      perform_enqueued_jobs(only: EventDispatcherJob) do
        create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, content: 'compre já')
      end

      expect(conversa.reload).to be_resolved
      expect(pesquisa).not_to have_received(:perform)
      expect(eventos_do_robo).not_to include('conversation_resolved', 'conversation_status_changed', 'conversation_updated')
      expect(automacao).not_to have_received(:perform)
    end

    it 'Spam automático em conversa nova do remetente no Spam: sem os três' do
      ConversaCanal::RemetenteNoSpam.create!(account: account, inbox: inbox, email: 'oferta@exemplo.com')

      nova = perform_enqueued_jobs(only: EventDispatcherJob) do
        create(:conversation, account: account, inbox: inbox, contact: contato)
      end

      expect(nova.reload).to be_resolved
      expect(pesquisa).not_to have_received(:perform)
      expect(eventos_do_robo).not_to include('conversation_resolved', 'conversation_status_changed', 'conversation_updated')
      expect(automacao).not_to have_received(:perform)
    end

    it 'Lixeira: resolve como o Resolver de sempre (pesquisa, robô e automação)' do
      mover('lixeira')

      expect(pesquisa).to have_received(:perform)
      expect(eventos_do_robo).to include('conversation_resolved', 'conversation_status_changed', 'conversation_updated')
      expect(automacao).to have_received(:perform)
    end

    it '"Não é spam": a reabertura dispara normal' do
      mover('spam')
      clear_enqueued_jobs

      mover('')

      expect(conversa.reload).to be_open
      expect(eventos_do_robo).to include('conversation_opened', 'conversation_status_changed', 'conversation_updated')
      expect(automacao).to have_received(:perform)
    end

    it 'com a chave conversa_email_nova desligada, os três seguem normais' do
      described_class.create!(account: account, conversation: conversa, pasta: 'spam')
      account.disable_features!('conversa_email_nova')

      perform_enqueued_jobs(only: EventDispatcherJob) { conversa.update!(status: :resolved) }

      expect(pesquisa).to have_received(:perform)
      expect(eventos_do_robo).to include('conversation_resolved', 'conversation_status_changed', 'conversation_updated')
      expect(automacao).to have_received(:perform)
    end
  end
end
