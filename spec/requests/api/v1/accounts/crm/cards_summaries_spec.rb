require 'rails_helper'

# Resumo por etapa e por dono (#2293): o card com várias conversas vinculadas conta uma vez e soma o valor uma vez.
RSpec.describe 'CRM resumo por etapa e por dono', type: :request do
  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Gestora Ana') }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }

  def conversation
    create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account), assignee: admin)
  end

  def card(title, value_cents:)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: title, inbox: inbox, owner: admin,
                              value_cents: value_cents, primary_conversation: conversation)
  end

  def groups(group_by)
    get "/api/v1/accounts/#{account.id}/crm/cards/summaries", params: { group_by: group_by, pipeline_id: pipeline_and_stage.first.id },
                                                              headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    response.parsed_body.dig('payload', 'groups')
  end

  before do
    many = card('Várias conversas', value_cents: 10_000)
    2.times { many.card_conversations.create!(account: account, conversation: conversation, linked_by: admin) }
    card('Uma conversa', value_cents: 5_000)
  end

  it 'conta cada card uma vez e soma o valor uma vez, por etapa e por dono' do
    stage = pipeline_and_stage.last

    expect(groups('stage')).to contain_exactly(include('key' => stage.id, 'count' => 2, 'sum_cents' => 15_000))
    expect(groups('owner')).to contain_exactly(include('key' => admin.id, 'count' => 2, 'sum_cents' => 15_000))
  end
end
