require 'rails_helper'

# Multifunil (#1147): a IA do card trabalha só no pedido que é o assunto atual e sabe dos outros pedidos da conversa.
RSpec.describe 'Crm AI por pedido (multifunil)' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:auto) { create_card('Cotação auto') }
  let(:casa) { create_card('Cotação residencial') }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  def create_card(title)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: title, contact: contact,
                              primary_conversation: conversation, currency: 'BRL')
  end

  def focar(card, at)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation).update!(focused_at: at)
  end

  describe Crm::Ai::Evaluator do
    before do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
        instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test', api_base: 'https://api.openai.com' })
      )
      focar(auto, 2.hours.ago)
      focar(casa, 1.minute.ago)
    end

    it 'não avalia o card que não é o assunto atual' do
      expect(Crm::Ai::StageClassifier).not_to receive(:new)

      result = described_class.new(card: auto).perform

      expect(result.status).to eq(:skipped)
      expect(result.error).to eq('not_current_subject')
    end

    it 'avalia qualquer card quando a pessoa pede (manual)' do
      classificacao = { suggested_stage_id: auto.stage_id, confidence: 0.1, reasoning: 'Sem sinal', model_used: 'gpt-5.4-mini' }
      classifier = instance_double(Crm::Ai::StageClassifier, perform: classificacao)
      allow(Crm::Ai::StageClassifier).to receive(:new).and_return(classifier)

      described_class.new(card: auto, trigger: 'manual').perform

      expect(classifier).to have_received(:perform)
    end
  end

  describe Crm::Ai::ContextBuilder do
    it 'lista os outros pedidos abertos da conversa, sem o próprio card' do
      casa
      pipeline, stage = pipeline_and_stage

      other = described_class.new(card: auto).perform[:other_subjects]

      expect(other).to eq([{ id: casa.id, title: 'Cotação residencial', pipeline: pipeline.name, stage: stage.name }])
    end

    it 'fica vazio quando a conversa tem um pedido só' do
      expect(described_class.new(card: auto).perform[:other_subjects]).to eq([])
    end

    it 'ignora pedido encerrado' do
      casa.update!(status: :archived)

      expect(described_class.new(card: auto).perform[:other_subjects]).to eq([])
    end
  end

  describe Crm::Cards::Focus do
    it 'agenda a avaliação do card que passou a ser o assunto atual' do
      observer = instance_double(Crm::Ai::Observer, schedule_evaluation: nil)
      allow(Crm::Ai::Observer).to receive(:new).with(card: casa).and_return(observer)

      described_class.new(account: account, card: casa, conversation: conversation).perform

      expect(observer).to have_received(:schedule_evaluation)
    end
  end
end
