require 'rails_helper'

# #1157 — a ação em massa confere, card a card, a mesma regra da ação individual. Antes só
# conferia `index?`: função com crm_view movia, reatribuía, fechava e arquivava cards.
RSpec.describe 'CRM cards bulk (Enterprise policy)', type: :request do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    previous_value.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_value
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:other_stage) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 2) }
  let(:card) { account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, title: 'Card visível') }
  let(:agent) { create(:user) }

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    create(:account_user, account: account, user: agent, role: :agent, custom_role: role)
  end

  def bulk(action_name, payload = {})
    post "/api/v1/accounts/#{account.id}/crm/cards/bulk",
         params: { ids: [card.id], action_name: action_name, payload: payload },
         headers: agent.create_new_auth_token, as: :json
  end

  def result = response.parsed_body['payload']

  context 'with only crm_view' do
    before { give_role(%w[crm_view]) }

    it 'does not move, reassign, close or archive the card' do
      bulk('move', stage_id: other_stage.id)
      bulk('assign', owner_id: agent.id)
      bulk('status', result: 'won')
      bulk('delete')

      expect(result['failed']).to eq([{ 'id' => card.id, 'error' => 'forbidden' }])
      card.reload
      expect([card.stage_id, card.owner_id, card.status]).to eq([stage.id, nil, 'open'])
    end
  end

  context 'with crm_move_cards' do
    before { give_role(%w[crm_view crm_move_cards]) }

    it 'moves but does not archive' do
      bulk('move', stage_id: other_stage.id)
      expect(result['updated']).to eq([card.id])

      bulk('delete')
      expect(result['failed']).to eq([{ 'id' => card.id, 'error' => 'forbidden' }])
      expect(card.reload.status).to eq('open')
    end
  end

  context 'with crm_manage_cards' do
    before { give_role(%w[crm_view crm_manage_cards]) }

    it 'archives the card' do
      bulk('delete')

      expect(result['updated']).to eq([card.id])
      expect(card.reload.status).to eq('archived')
    end
  end

  context 'with a plain agent (no custom role)' do
    before { create(:account_user, account: account, user: agent, role: :agent) }

    it 'keeps moving cards as before' do
      bulk('move', stage_id: other_stage.id)

      expect(result['updated']).to eq([card.id])
      expect(card.reload.stage_id).to eq(other_stage.id)
    end
  end
end
