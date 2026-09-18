require 'rails_helper'

RSpec.describe AutomationRules::CrmActions do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:next_stage) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta') }
  let(:conversation) { create(:conversation, account: account) }
  let(:rule) { create(:automation_rule, account: account) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def create_card(status: :open)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversation.contact,
                              primary_conversation: conversation, title: 'Lead', status: status)
  end

  describe AutomationRules::ActionService do
    def run_action(action_name, params = [])
      rule.update!(actions: [{ action_name: action_name, action_params: params }])
      described_class.new(rule, account, conversation).perform
    end

    it 'crm_create_card cria o card na etapa escolhida, ligado à conversa' do
      run_action('crm_create_card', [next_stage.id])

      card = Crm::Cards::ConversationCardFinder.new(account: account).find(conversation)
      expect(card).to have_attributes(pipeline_id: pipeline.id, stage_id: next_stage.id, contact_id: conversation.contact_id)
    end

    it 'crm_create_card não duplica quando a conversa já tem card' do
      create_card

      expect { run_action('crm_create_card', [next_stage.id]) }.not_to change(Crm::Card, :count)
    end

    it 'crm_create_card ignora etapa de outra conta' do
      other_account = create(:account)
      _, foreign_stage = create_crm_pipeline(account: other_account, user: create(:user, account: other_account))

      expect { run_action('crm_create_card', [foreign_stage.id]) }.not_to change(Crm::Card, :count)
    end

    it 'crm_move_card_stage move o card da conversa' do
      card = create_card

      run_action('crm_move_card_stage', [next_stage.id])

      expect(card.reload.stage_id).to eq(next_stage.id)
    end

    it 'crm_mark_card_won e crm_mark_card_lost fecham o card' do
      card = create_card

      run_action('crm_mark_card_won')
      expect(card.reload).to be_won

      run_action('crm_mark_card_lost')
      expect(card.reload).to be_lost
    end

    it 'crm_assign_card_owner define o dono só com agente da conta' do
      card = create_card
      outsider = create(:user)

      run_action('crm_assign_card_owner', [outsider.id])
      expect(card.reload.owner_id).not_to eq(outsider.id)

      run_action('crm_assign_card_owner', [user.id])
      expect(card.reload.owner_id).to eq(user.id)
    end

    it 'não faz nada com o CRM desligado' do
      with_modified_env(CRM_KANBAN_ENABLED: 'false') do
        expect { run_action('crm_create_card', [next_stage.id]) }.not_to change(Crm::Card, :count)
      end
    end
  end

  describe AutomationRules::ConditionsFilterService do
    def matches?(attribute_key, filter_operator, values = [])
      rule.update!(conditions: [{ attribute_key: attribute_key, filter_operator: filter_operator,
                                  values: values, query_operator: nil }])
      described_class.new(rule, conversation).perform
    end

    it 'filtra por etapa do card' do
      create_card

      expect(matches?('crm_stage_id', 'equal_to', [stage.id])).to be(true)
      expect(matches?('crm_stage_id', 'equal_to', [next_stage.id])).to be(false)
      expect(matches?('crm_stage_id', 'not_equal_to', [next_stage.id])).to be(true)
    end

    it 'filtra por funil e pela existência de card' do
      expect(matches?('crm_pipeline_id', 'is_not_present')).to be(true)
      expect(matches?('crm_pipeline_id', 'not_equal_to', [pipeline.id])).to be(true)

      create_card

      expect(matches?('crm_pipeline_id', 'is_present')).to be(true)
      expect(matches?('crm_pipeline_id', 'equal_to', [pipeline.id])).to be(true)
    end

    it 'filtra por status do card e ignora card arquivado' do
      card = create_card(status: :won)

      expect(matches?('crm_card_status', 'equal_to', ['won'])).to be(true)
      expect(matches?('crm_card_status', 'equal_to', ['open'])).to be(false)

      card.update!(status: :archived)
      expect(matches?('crm_pipeline_id', 'is_present')).to be(false)
    end

    it 'acha o card vinculado à conversa (não só o principal)' do
      other_conversation = create(:conversation, account: account)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversation.contact,
                                       primary_conversation: other_conversation, title: 'Lead')
      Crm::CardConversation.create!(account: account, card: card, conversation: conversation)

      expect(matches?('crm_stage_id', 'equal_to', [stage.id])).to be(true)
    end

    it 'rejeita operador não suportado' do
      expect(matches?('crm_stage_id', 'is_present')).to be(false)
    end
  end
end
