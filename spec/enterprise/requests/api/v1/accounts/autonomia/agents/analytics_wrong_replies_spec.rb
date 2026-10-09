require 'rails_helper'

RSpec.describe 'Autonomia wrong-reply analytics drawer (Enterprise)', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:other_account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, name: 'Caixa visível') }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:agent_bot) { create(:agent_bot, account: account, name: 'Clara espelho', outgoing_url: nil) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def create_conversation(target_inbox, contact: nil)
    create(:conversation, account: account, inbox: target_inbox, contact: contact)
  end

  def create_agent_message(conversation, content:, created_at: Time.current)
    message = create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                               message_type: :outgoing, sender: agent_bot, content: content,
                               content_attributes: { 'autonomia_agent_id' => agent.id })
    message.update!(created_at: created_at, updated_at: created_at)
    message
  end

  def mark_agent_touched(conversation, created_at: Time.current)
    event = Autonomia::Agents::AgentEvent.create!(agent: agent, account: account,
                                                  conversation_id: conversation.id, event_type: :replied)
    event.update!(created_at: created_at)
    event
  end

  def create_report(message, description: nil, created_at: Time.current, reason: 'incorrect_information')
    report = create(:captain_message_report, account: account, conversation: message.conversation,
                                             message: message, user: administrator,
                                             report_reason: reason, description: description)
    report.update!(created_at: created_at, updated_at: created_at)
    report
  end

  def request_drawer(user: administrator, target_account: account, target_agent: agent, range: '30d')
    get "/api/v1/accounts/#{target_account.id}/autonomia/agents/#{target_agent.id}/analytics/conversations",
        params: { metric: 'wrong_replies', range: range },
        headers: user.create_new_auth_token,
        as: :json
  end

  def grant_drawer_access(user, permissions:, member_inbox: inbox)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by!(account: account).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: member_inbox)
  end

  it 'returns one DTO row per marking, including repeated reports and messages in one conversation' do
    conversation = create_conversation(inbox)
    first_message = create_agent_message(conversation, content: 'Primeira resposta')
    second_message = create_agent_message(conversation, content: 'Segunda resposta')
    mark_agent_touched(conversation)
    first_report = create_report(first_message, description: 'Resposta sugerida um',
                                                created_at: 3.minutes.ago)
    second_report = create_report(second_message, description: nil, created_at: 2.minutes.ago,
                                                  reason: 'incomplete_response')
    repeated_report = create_report(first_message, description: 'Resposta sugerida dois',
                                                   created_at: 1.minute.ago, reason: 'other')

    request_drawer

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['meta']).to include(
      'metric' => 'wrong_replies', 'range' => '30d', 'limit' => 50,
      'count' => 3, 'total_count' => 3, 'hidden_count' => 0,
      'has_hidden' => false, 'has_more' => false
    )
    expect(body['payload'].map { |row| row['report_id'] }).to eq(
      [repeated_report.id, second_report.id, first_report.id]
    )

    row = body['payload'].find { |item| item['report_id'] == first_report.id }
    expect(row).to include(
      'report_id' => first_report.id,
      'conversation_id' => conversation.id,
      'message_id' => first_message.id,
      'report_reason' => 'incorrect_information',
      'suggested_answer' => 'Resposta sugerida um',
      'message' => 'Primeira resposta',
      'reason_label' => a_kind_of(String),
      'reported_at' => a_kind_of(String)
    )
    expect(row['conversation']).to include(
      'id' => conversation.id,
      'display_id' => conversation.display_id,
      'inbox_id' => inbox.id,
      'inbox_name' => inbox.name
    )
    empty_suggestion = body['payload'].find { |item| item['report_id'] == second_report.id }
    expect(empty_suggestion['suggested_answer']).to be_nil
  end

  it 'does not expose a private Autonomia agent note in the drawer' do
    conversation = create_conversation(inbox)
    mark_agent_touched(conversation)
    private_note = create(:message, account: account, inbox: inbox, conversation: conversation,
                                    message_type: :outgoing, sender: agent_bot, private: true,
                                    content: 'Nota interna',
                                    content_attributes: { 'autonomia_agent_id' => agent.id })
    create_report(private_note)

    request_drawer

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['meta']).to include(
      'count' => 0, 'total_count' => 0, 'hidden_count' => 0,
      'has_hidden' => false, 'has_more' => false
    )
    expect(response.parsed_body['payload']).to be_empty
  end

  it 'lets an administrator see every same-account marking' do
    hidden_inbox = create(:inbox, account: account, name: 'Caixa restrita')
    visible_conversation = create_conversation(inbox)
    hidden_conversation = create_conversation(hidden_inbox)
    visible_message = create_agent_message(visible_conversation, content: 'Visível')
    hidden_message = create_agent_message(hidden_conversation, content: 'Conteúdo restrito')
    mark_agent_touched(visible_conversation)
    mark_agent_touched(hidden_conversation)
    visible_report = create_report(visible_message, description: 'Sugestão visível', created_at: 2.minutes.ago)
    hidden_report = create_report(hidden_message, description: 'Sugestão restrita', created_at: 1.minute.ago)

    request_drawer

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body.dig('meta', 'total_count')).to eq(2)
    expect(body['payload'].pluck('report_id')).to contain_exactly(visible_report.id, hidden_report.id)
  end

  it 'filters conversations before ordering and limiting reports for a custom-role member' do
    restricted_inbox = create(:inbox, account: account, name: 'Caixa sem acesso')
    viewer = create(:user, account: account, role: :agent)
    grant_drawer_access(viewer, permissions: %w[autonomia_view conversation_manage])

    visible_conversation = create_conversation(inbox)
    hidden_contact = create(:contact, account: account, name: 'Contato oculto')
    hidden_conversation = create_conversation(restricted_inbox, contact: hidden_contact)
    visible_message = create_agent_message(visible_conversation, content: 'Resposta que pode ver')
    hidden_message = create_agent_message(hidden_conversation, content: 'SEGREDO OCULTO')
    mark_agent_touched(visible_conversation)
    mark_agent_touched(hidden_conversation)
    visible_report = create_report(visible_message, description: 'Sugestão disponível', created_at: 2.minutes.ago)
    create_report(hidden_message, description: 'Sugestão que não pode vazar', created_at: 1.minute.ago)

    request_drawer(user: viewer)

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['meta']).to include(
      'count' => 1, 'total_count' => 2, 'hidden_count' => 1,
      'has_hidden' => true, 'has_more' => false
    )
    expect(body['payload'].pluck('report_id')).to eq([visible_report.id])
    expect(response.body).not_to include('SEGREDO OCULTO', 'Contato oculto', 'Sugestão que não pode vazar')
  end

  it 'reports 51 visible markings while returning only 50, without deduplicating them' do
    restricted_inbox = create(:inbox, account: account, name: 'Caixa sem acesso')
    viewer = create(:user, account: account, role: :agent)
    grant_drawer_access(viewer, permissions: %w[autonomia_view conversation_manage])
    visible_conversation = create_conversation(inbox)
    hidden_conversation = create_conversation(restricted_inbox)
    mark_agent_touched(visible_conversation)
    mark_agent_touched(hidden_conversation)

    visible_reports = Array.new(51) do |index|
      message = create_agent_message(visible_conversation, content: "Resposta #{index}")
      create_report(message, description: "Sugestão #{index}", created_at: (index + 2).seconds.ago)
    end
    hidden_message = create_agent_message(hidden_conversation, content: 'Não pode aparecer')
    create_report(hidden_message, description: 'Oculto', created_at: 1.second.ago)

    request_drawer(user: viewer)

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['meta']).to include(
      'count' => 51, 'total_count' => 52, 'hidden_count' => 1,
      'has_hidden' => true, 'has_more' => true
    )
    expect(body['payload'].length).to eq(50)
    expect(body['payload'].map { |row| row['report_id'] }).to eq(
      visible_reports.sort_by { |report| [-report.created_at.to_f, -report.id] }.first(50).map(&:id)
    )
    expect(body['payload'].pluck('message')).not_to include('Não pode aparecer')
  end

  it 'returns no rows but keeps hidden_count for a member without conversation permission' do
    viewer = create(:user, account: account, role: :agent)
    grant_drawer_access(viewer, permissions: ['autonomia_view'])
    conversation = create_conversation(inbox)
    message = create_agent_message(conversation, content: 'Sem permissão')
    mark_agent_touched(conversation)
    create_report(message, description: 'Não exibir')

    request_drawer(user: viewer)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['meta']).to include(
      'count' => 0, 'total_count' => 1, 'hidden_count' => 1, 'has_hidden' => true,
      'has_more' => false
    )
    expect(response.parsed_body['payload']).to be_empty
    expect(response.body).not_to include('Sem permissão', 'Não exibir')
  end

  it 'excludes a report outside the selected window' do
    conversation = create_conversation(inbox)
    message = create_agent_message(conversation, content: 'Resposta antiga')
    mark_agent_touched(conversation)
    old_report = create_report(message, description: 'Fora da janela', created_at: 31.days.ago)

    request_drawer

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['meta']).to include(
      'count' => 0, 'total_count' => 0, 'hidden_count' => 0,
      'has_hidden' => false, 'has_more' => false
    )
    expect(response.parsed_body['payload']).to be_empty
    expect(old_report.reload.created_at).to be < 30.days.ago
  end

  it 'returns 404 for an agent from another account or an archived agent' do
    foreign_agent = Autonomia::Agents::Agent.create!(account: other_account, name: 'Outro', agent_type: 'custom',
                                                     status: :active, enabled: true, instruction: 'Atenda.')

    request_drawer(target_agent: foreign_agent)
    expect(response).to have_http_status(:not_found)

    agent.update!(deleted_at: Time.current)
    request_drawer
    expect(response).to have_http_status(:not_found)
  end
end
