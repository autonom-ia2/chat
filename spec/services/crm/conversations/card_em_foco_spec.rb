require 'rails_helper'

# #1675: toda mensagem do cliente avalia o card em foco (flag crm_avaliar_toda_mensagem), também na caixa de 2+ funis.
RSpec.describe Crm::Conversations::CardEmFoco do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Joana Lima') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let!(:auto) { create_card(vendas, 'Seguro auto', focused_at: 1.minute.ago) }
  let!(:residencial) { create_card(pos_venda, 'Seguro residencial', focused_at: 2.minutes.ago) }
  let(:identifier) { instance_double(Crm::Subjects::Identifier) }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    [vendas, pos_venda].each do |pipeline, stage|
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: false,
                                           created_by: admin)
    end
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: :off)
    account.enable_features!(described_class::FLAG)
    allow(Crm::Subjects::Identifier).to receive(:new).and_return(identifier)
    clear_enqueued_jobs
  end

  def create_card(pipeline_and_stage, title, focused_at:)
    pipeline, stage = pipeline_and_stage
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, primary_conversation: conversation,
                                     inbox: inbox, title: title, last_activity_at: 3.days.ago, last_message_at: 3.days.ago)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: focused_at)
    card
  end

  def incoming(content = 'Fechado, quero contratar')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def sincronizar(message)
    Crm::Conversations::CardSyncer.new(conversation: conversation.reload, message: message).perform
  end

  def avaliacoes_agendadas
    enqueued_jobs.select { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }.map { |job| job['arguments'].first }
  end

  # Roda as avaliações agendadas depois do debounce e devolve os cards que a IA de fato leu.
  def avaliados
    lidos = []
    allow(Crm::Ai::Evaluator).to receive(:new) do |card:, **|
      lidos << card.id
      instance_double(Crm::Ai::Evaluator, perform: nil)
    end
    jobs = enqueued_jobs.select { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }
    travel(Crm::Ai::Config::DEBOUNCE_SECONDS.seconds + 1.second) do
      jobs.each { |job| Crm::Ai::EvaluateCardJob.perform_now(*job['arguments']) }
    end
    lidos
  end

  describe 'com a IA de assunto desligada na caixa de 2 funis' do
    it 'a mensagem no mesmo assunto agenda a IA no card em foco e conta como atividade dele', :aggregate_failures do
      message = incoming

      expect(sincronizar(message)).to eq(auto)

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(auto.reload.last_activity_at).to be_within(1.second).of(message.created_at)
      expect(auto.last_message_at).to be_within(1.second).of(message.created_at)
      expect(residencial.reload.last_activity_at).to be < 1.day.ago
      expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(auto, Events::Types::CRM_CARD_UPDATED)
      expect(avaliados).to eq([auto.id])
    end

    it 'uma rajada de mensagens dá uma avaliação só' do
      3.times { |i| sincronizar(incoming("parte #{i}")) }

      expect(avaliacoes_agendadas.uniq).to eq([auto.id])
      expect(avaliados).to eq([auto.id])
    end

    it 'mensagem da equipe não agenda nem mexe na atividade' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Já te mando')

      sincronizar(message)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
    end

    it 'não volta a atividade que uma ação mais nova gravou' do
      message = incoming
      auto.update!(last_activity_at: 1.minute.from_now)

      sincronizar(message)

      expect(auto.reload.last_activity_at).to be > message.created_at
      expect(avaliacoes_agendadas).to eq([auto.id])
    end

    it 'a atividade é a hora da mensagem do cliente, não a da resposta que veio depois' do
      message = incoming
      travel(1.minute) do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Já te mando')
      end

      sincronizar(message)

      expect(auto.reload.last_activity_at).to be_within(1.second).of(message.created_at)
      expect(auto.last_message_at).to be_within(1.second).of(message.created_at)
    end

    it 'com a IA do CRM desligada, nada muda' do
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)

      sincronizar(incoming)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
    end

    it 'com o CRM desligado na caixa, nada muda' do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(crm_enabled: false)

      sincronizar(incoming)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
    end

    it 'sem a flag, tudo como hoje: nem avaliação, nem atividade, nem trava' do
      account.disable_features!(described_class::FLAG)
      allow(Crm::Conversations::SyncLock).to receive(:new).and_call_original

      sincronizar(incoming)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
      expect(Crm::Conversations::SyncLock).not_to have_received(:new)
    end
  end

  describe 'com a IA de assunto ligada na caixa de 2 funis' do
    before { account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :auto) }

    it 'o CardSyncer espera a decisão do assunto: não agenda nem mexe no card' do
      sincronizar(incoming)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
    end

    it 'assunto mantido: depois da decisão, a IA avalia o card em foco', :aggregate_failures do
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      message = incoming
      sincronizar(message)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(auto.reload.last_activity_at).to be_within(1.second).of(message.created_at)
      expect(avaliados).to eq([auto.id])
    end

    it 'a decisão quebrou (Jev fora): a mensagem é avaliada mesmo assim' do
      allow(identifier).to receive(:perform).and_raise(RuntimeError, 'Jev fora')
      message = incoming

      expect { Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id) }.to raise_error(RuntimeError, 'Jev fora')

      expect(avaliacoes_agendadas).to eq([auto.id])
    end

    it 'troca de assunto: avalia o card novo do foco, uma vez só' do
      allow(identifier).to receive(:perform) do
        Crm::Subjects::Acoes.focar(conversation: conversation, card: residencial)
        instance_double(Crm::SubjectDecision, state: 'applied')
      end
      message = incoming('E o residencial, já renovou?')
      sincronizar(message)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliacoes_agendadas).to eq([residencial.id])
      expect(avaliados).to eq([residencial.id])
    end

    it 'rajada: a mensagem que não é a última fica para o job da seguinte, que avalia uma vez' do
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      primeira = incoming('Fechado')
      segunda = incoming('quero contratar')

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, primeira.id)
      expect(avaliacoes_agendadas).to be_empty

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, segunda.id)
      expect(avaliacoes_agendadas).to eq([auto.id])
    end

    it 'texto recuperado pelo Híbrido depois da avaliação: a IA relê o card (#1638)' do
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      message = incoming('Mensagem não suportada')
      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      travel(1.minute) do
        message.update!(content: 'Fechado, quero contratar', content_attributes: { 'hybrid_recovered_at' => Time.current.utc.iso8601 })
        Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)
      end

      expect(avaliacoes_agendadas).to eq([auto.id, auto.id])
    end

    it 'sem a flag, depois da decisão nada é agendado (como hoje)' do
      account.disable_features!(described_class::FLAG)
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      message = incoming

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliacoes_agendadas).to be_empty
    end
  end

  describe 'na caixa de 1 funil com card ao chegar' do
    before do
      account.crm_pipeline_inboxes.find_by(pipeline: pos_venda.first).destroy!
      account.crm_pipeline_inboxes.find_by(pipeline: vendas.first).update!(auto_create_card: true)
      account.crm_inbox_settings.find_by(inbox: inbox).update!(auto_create_card: true)
      residencial.update!(status: :archived)
    end

    it 'com a IA de assunto desligada: o card ao chegar avalia, como hoje, sem segunda avaliação' do
      allow(described_class).to receive(:new).and_call_original

      sincronizar(incoming)

      expect(described_class).not_to have_received(:new)
      expect(avaliados).to eq([auto.id])
    end

    it 'com a IA de assunto ligada: o card ao chegar já agendou, e a decisão não agenda de novo' do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :auto)
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      message = incoming
      sincronizar(message)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(avaliados).to eq([auto.id])
    end
  end
end
