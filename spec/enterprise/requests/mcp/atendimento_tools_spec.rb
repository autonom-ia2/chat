require 'rails_helper'

# Ferramentas da Onda 1 do MCP nativo (#3090), além das cinco que vieram do upstream.
RSpec.describe 'MCP tools de atendimento', type: :request do
  include McpSpecHelpers

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Loja') }
  let(:application) { Doorkeeper::Application.create!(name: 'Em d.ia', redirect_uri: 'https://emd.ia.br/volta', confidential: false) }
  let(:scopes) { 'conversations:read conversations:write contacts:read contacts:write reports:read' }
  let(:access_token) do
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id, account_id: account.id, scopes: scopes,
                                    expires_in: 2.hours)
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    InstallationConfig.where(name: 'OAUTH_PROVIDER_ENABLED').delete_all
    InstallationConfig.create!(name: 'OAUTH_PROVIDER_ENABLED', value: true)
  end

  after { GlobalConfig.clear_cache }

  def structured(name, arguments = {})
    result = call_mcp_tool(name, arguments, access_token)
    expect(result['isError']).to be(false), result.to_s
    result['structuredContent']
  end

  it 'lists inboxes, labels, teams, agents and canned responses of the account only' do
    inbox
    create(:label, account: account, title: 'vip')
    create(:team, account: account, name: 'Vendas')
    create(:canned_response, account: account, short_code: 'oi', content: 'Olá, tudo bem?')
    create(:inbox, name: 'De outra conta')

    expect(structured('list_inboxes')['inboxes'].pluck('name')).to eq(['WhatsApp Loja'])
    expect(structured('list_labels')['labels'].pluck('title')).to eq(['vip'])
    expect(structured('list_teams')['teams'].pluck('name')).to eq(['vendas'])
    expect(structured('list_agents')['agents'].pluck('id')).to eq([admin.id])
    expect(structured('list_canned_responses', { search: 'tudo' })['canned_responses'].pluck('short_code')).to eq(['oi'])
  end

  describe 'assign_conversation' do
    it 'assigns an agent and a team, and removes them with 0' do
      agent = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agent, inbox: inbox)
      team = create(:team, account: account)

      structured('assign_conversation', { conversation_id: conversation.display_id, agent_id: agent.id, team_id: team.id })
      expect(conversation.reload).to have_attributes(assignee: agent, team: team)

      structured('assign_conversation', { conversation_id: conversation.display_id, agent_id: 0, team_id: 0 })
      expect(conversation.reload).to have_attributes(assignee: nil, team: nil)
    end

    it 'does not assign an agent who is not in the inbox of the conversation' do
      agent = create(:user, account: account, role: :agent)

      result = call_mcp_tool('assign_conversation', { conversation_id: conversation.display_id, agent_id: agent.id }, access_token)

      expect(result['isError']).to be(true)
      expect(conversation.reload.assignee).to be_nil
    end

    it 'does not assign someone from another account' do
      outsider = create(:user)

      result = call_mcp_tool('assign_conversation', { conversation_id: conversation.display_id, agent_id: outsider.id }, access_token)

      expect(result['isError']).to be(true)
      expect(conversation.reload.assignee).to be_nil
    end
  end

  describe 'contacts' do
    let(:contact) { create(:contact, account: account, name: 'Maria') }

    it 'reads a contact with notes and conversations' do
      create(:conversation, account: account, inbox: inbox, contact: contact)
      contact.notes.create!(account: account, user: admin, content: 'Prefere WhatsApp')

      data = structured('get_contact', { contact_id: contact.id })

      expect(data).to include('name' => 'Maria')
      expect(data['notes'].pluck('content')).to eq(['Prefere WhatsApp'])
      expect(data['conversations'].size).to eq(1)
    end

    it 'does not read a contact of another account' do
      result = call_mcp_tool('get_contact', { contact_id: create(:contact).id }, access_token)

      expect(result['isError']).to be(true)
    end

    it 'creates and updates a contact, merging custom attributes and checking labels' do
      created = structured('create_contact', { name: 'João', email: 'joao@example.com' })
      create(:label, account: account, title: 'cliente')

      structured('update_contact', { contact_id: created['id'], phone_number: '+5511999990000', labels: ['cliente'],
                                     custom_attributes: { plano: 'ouro' } })

      expect(Contact.find(created['id'])).to have_attributes(phone_number: '+5511999990000', label_list: ['cliente'],
                                                             custom_attributes: { 'plano' => 'ouro' })
    end

    it 'refuses labels that do not exist in the account' do
      result = call_mcp_tool('update_contact', { contact_id: contact.id, labels: ['inventada'] }, access_token)

      expect(result['isError']).to be(true)
      expect(contact.reload.label_list).to be_empty
    end

    it 'adds a note signed by the user' do
      structured('add_contact_note', { contact_id: contact.id, content: 'Ligar amanhã' })

      expect(contact.notes.last).to have_attributes(content: 'Ligar amanhã', user: admin)
    end
  end

  it 'lists and reads companies of the account' do
    company = Company.create!(account: account, name: 'Padaria Central', domain: 'padaria.com.br')
    create(:contact, account: account, company: company)

    expect(structured('list_companies', { search: 'padaria' })['companies'].pluck('id')).to eq([company.id])
    expect(structured('get_company', { company_id: company.id })['contacts'].size).to eq(1)
  end

  it 'summarizes a period and the period before it' do
    data = structured('get_report_summary', { since: '2026-11-01', until: '2026-11-07' })

    expect(data['period']).to include('conversations_count')
    expect(data['previous_period']).to include('conversations_count')
    expect(Time.zone.parse(data['period']['since'])).to eq(Time.zone.parse('2026-11-01T00:00:00-03:00'))
    expect(Time.zone.parse(data['previous_period']['since'])).to eq(Time.zone.parse('2026-10-25T00:00:00-03:00'))
    expect(Time.zone.parse(data['previous_period']['until'])).to eq(Time.zone.parse('2026-10-31T23:59:59-03:00'))
  end

  it 'answers a readable error for a date that does not exist' do
    result = call_mcp_tool('get_report_summary', { since: '2026-11-01', until: '2026-02-30' }, access_token)

    expect(result['isError']).to be(true)
  end

  it 'refuses a write without the write scope' do
    access_token.update!(scopes: 'contacts:read')

    result = call_mcp_tool('create_contact', { name: 'Sem permissão' }, access_token)

    expect(result['isError']).to be(true)
    expect(Contact.where(name: 'Sem permissão')).to be_empty
  end
end
