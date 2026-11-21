require 'rails_helper'

# The platform_* tools (#3106) drive the Guide's engine: they go through the real endpoints, as the user, and the
# effect is checked in the database, never on a double of the transport.
RSpec.describe 'MCP platform tools', type: :request do
  include McpSpecHelpers

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:application) { Doorkeeper::Application.create!(name: 'Em d.ia', redirect_uri: 'https://emd.ia.br/volta', confidential: false) }
  let(:scopes) { 'platform:read platform:write' }
  let(:access_token) do
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id, account_id: account.id, scopes: scopes,
                                    expires_in: 2.hours)
  end

  before do
    InstallationConfig.where(name: 'OAUTH_PROVIDER_ENABLED').delete_all
    InstallationConfig.create!(name: 'OAUTH_PROVIDER_ENABLED', value: true)
  end

  after { GlobalConfig.clear_cache }

  def mcp_audits
    account.associated_audits.where(action: 'mcp_action')
  end

  describe 'platform_catalog' do
    it 'lists the write actions that contain the filter' do
      result = call_mcp_tool('platform_catalog', { kind: 'write', filter: 'LABELS' }, access_token)

      expect(result.dig('structuredContent', 'entries')).to include('POST labels', 'DELETE labels/:id')
      expect(result.dig('structuredContent', 'entries')).to all(include('labels'))
    end

    it 'lists the resources platform_read accepts' do
      result = call_mcp_tool('platform_catalog', { kind: 'read' }, access_token)

      expect(result.dig('structuredContent', 'entries')).to include('labels', 'inboxes')
    end
  end

  describe 'platform_read' do
    it 'reads the account through the endpoint the screen calls' do
      create(:label, account: account, title: 'vip')

      result = call_mcp_tool('platform_read', { resource: 'labels' }, access_token)

      expect(result['isError']).to be(false)
      expect(result.dig('content', 0, 'text')).to include('vip')
    end

    it 'reads another account the user administers' do
      other = create(:account)
      create(:account_user, account: other, user: admin, role: :administrator)
      create(:label, account: other, title: 'da-outra')

      result = call_mcp_tool('platform_read', { resource: 'labels', account_id: other.id }, access_token)

      expect(result.dig('content', 0, 'text')).to include('da-outra')
    end
  end

  describe 'platform_action' do
    it 'does what can be undone at once, keeps it undoable and names the app in the audit log', :aggregate_failures do
      result = call_mcp_tool('platform_action', { action: 'POST labels', description: 'Criar a etiqueta vip.', body: { title: 'vip' } },
                             access_token)

      expect(result['isError']).to be(false)
      expect(account.labels.find_by(title: 'vip')).to be_present
      expect(mcp_audits.sole.audited_changes).to include('acao' => 'POST labels', 'frase' => 'Criar a etiqueta vip.', 'app' => 'Em d.ia')
      expect(Autonomia::Guide::Execucao.where(account: account, user: admin).sole.passos.first).to include('acao' => 'POST labels', 'ok' => true)
    end

    it 'refuses what cannot be undone until the user confirmed it, and then does it', :aggregate_failures do
      inbox = create(:inbox, account: account)
      create(:inbox_member, inbox: inbox, user: admin)
      conversation = create(:conversation, account: account, inbox: inbox)
      arguments = { action: 'POST conversations/:conversation_id/messages', description: 'Responder ao cliente.',
                    path: { conversation_id: conversation.display_id }, body: { content: 'Olá!' } }

      refused = call_mcp_tool('platform_action', arguments, access_token)
      expect(refused['isError']).to be(true)
      expect(refused.dig('content', 0, 'text')).to include('confirmed: true')
      expect(conversation.messages.where(content: 'Olá!')).to be_empty

      done = call_mcp_tool('platform_action', arguments.merge(confirmed: true), access_token)
      expect(done['isError']).to be(false)
      expect(conversation.messages.where(content: 'Olá!').count).to eq(1)
      expect(mcp_audits.sole.audited_changes['app']).to eq('Em d.ia')
    end

    it 'refuses an action outside the catalog and names the neighbours' do
      result = call_mcp_tool('platform_action', { action: 'POST label', description: 'x', body: { title: 'x' } }, access_token)

      expect(result['isError']).to be(true)
      expect(result.dig('content', 0, 'text')).to include('platform_catalog')
      expect(account.labels.count).to eq(0)
    end

    it 'needs platform:write' do
      read_only = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id, account_id: account.id,
                                                  scopes: 'platform:read', expires_in: 2.hours)

      result = call_mcp_tool('platform_action', { action: 'POST labels', description: 'x', body: { title: 'x' } }, read_only)

      expect(result['isError']).to be(true)
      expect(account.labels.count).to eq(0)
    end
  end
end
