require 'rails_helper'

# chat#1626 — a API pública de robôs (Configurações › Agentes externos) não lista nem deixa mexer no espelho.
RSpec.describe 'Agent bots API without platform agent mirrors', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Agente IA', agent_type: 'custom') }
  let!(:mirror) { create(:agent_bot, account: account, name: 'Espelho do agente', outgoing_url: nil) }
  let!(:external) { create(:agent_bot, account: account, name: 'Robo n8n', outgoing_url: 'https://n8n.example.com/hook') }
  let!(:link) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: mirror) }
  let(:base) { "/api/v1/accounts/#{account.id}/agent_bots" }

  def listed_ids
    get base, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body.pluck('id')
  end

  describe 'GET index' do
    it 'lists the external bot and system bots but not the mirror' do
      system_bot = create(:agent_bot, account: nil, name: 'Robo do sistema')

      ids = listed_ids

      expect(ids).to include(external.id, system_bot.id)
      expect(ids).not_to include(mirror.id)
    end

    it 'keeps hiding the mirror of a logically deleted link' do
      link.update!(deleted_at: Time.current)

      expect(listed_ids).not_to include(mirror.id)
    end
  end

  describe 'member actions on a mirror' do
    it 'returns 404 on show' do
      get "#{base}/#{mirror.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 on update and keeps the mirror unchanged' do
      patch "#{base}/#{mirror.id}", headers: headers, params: { name: 'Mudou', outgoing_url: 'https://x.example.com' },
                                    as: :json

      expect(response).to have_http_status(:not_found)
      expect(mirror.reload.name).to eq('Espelho do agente')
      expect(mirror.outgoing_url).to be_nil
    end

    it 'returns 404 on destroy and keeps the mirror and the link' do
      delete "#{base}/#{mirror.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(AgentBot.exists?(mirror.id)).to be(true)
      expect(link.reload.agent_bot_id).to eq(mirror.id)
    end

    it 'returns 404 on avatar and reset_access_token' do
      token = mirror.access_token.token

      delete "#{base}/#{mirror.id}/avatar", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      post "#{base}/#{mirror.id}/reset_access_token", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(mirror.access_token.reload.token).to eq(token)
    end
  end

  describe 'member actions on an external bot' do
    it 'shows, updates and destroys it' do
      get "#{base}/#{external.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['name']).to eq('Robo n8n')

      patch "#{base}/#{external.id}", headers: headers, params: { name: 'Robo n8n novo' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(external.reload.name).to eq('Robo n8n novo')

      delete "#{base}/#{external.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(AgentBot.exists?(external.id)).to be(false)
    end
  end

  describe 'account isolation' do
    it 'does not list or expose bots of another account' do
      other = create(:account)
      foreign_external = create(:agent_bot, account: other, name: 'Robo de fora', outgoing_url: 'https://other.example.com/hook')

      expect(listed_ids).not_to include(foreign_external.id)

      get "#{base}/#{foreign_external.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      delete "#{base}/#{foreign_external.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(AgentBot.exists?(foreign_external.id)).to be(true)
    end

    it 'does not hide a bot of this account because of a link in another account' do
      other = create(:account)
      other_agent = Autonomia::Agents::Agent.create!(account: other, name: 'Agente de fora', agent_type: 'custom')
      other_mirror = create(:agent_bot, account: other, outgoing_url: nil)
      Autonomia::Agents::AgentInbox.create!(agent: other_agent, inbox: create(:inbox, account: other), account: other,
                                            agent_bot: other_mirror)

      expect(listed_ids).to include(external.id)
      get "#{base}/#{other_mirror.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
