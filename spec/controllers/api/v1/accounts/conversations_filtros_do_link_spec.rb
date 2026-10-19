require 'rails_helper'

# Filtros pelo link na caixa (Números F2, #1883): a lista e o meta aceitam da_ia e esperando_min.
RSpec.describe 'Conversations API: filtros pelo link', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:da_ia_esperando) { conversa(1.hour.ago).tap { |c| passagem(c) } }
  let!(:da_ia_respondida) { conversa(nil).tap { |c| passagem(c) } }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    conversa(1.hour.ago) # esperando, sem passagem da IA
  end

  def conversa(waiting_since)
    create(:conversation, account: account, inbox: inbox).tap { |c| c.update!(waiting_since: waiting_since) }
  end

  def passagem(conversation)
    Crm::Passagem.create!(account: account, conversation: conversation, de_type: 'Autonomia::Agents::Agent', de_id: 1,
                          para_type: 'User', para_id: agent.id, motivo: 'passar_para', em: Time.current)
  end

  def get_json(path, **params)
    get "/api/v1/accounts/#{account.id}/conversations#{path}", headers: agent.create_new_auth_token,
                                                               params: { assignee_type: 'all' }.merge(params)
    expect(response).to have_http_status(:success)
    response.parsed_body
  end

  it 'da_ia=1 filtra a lista e a contagem' do
    data = get_json('', da_ia: '1')['data']

    expect(data['payload'].pluck('id')).to contain_exactly(da_ia_esperando.display_id, da_ia_respondida.display_id)
    expect(data['meta']['all_count']).to eq(2)
  end

  it 'os dois juntos no meta da lista' do
    meta = get_json('/meta', da_ia: '1', esperando_min: '30')['meta']

    expect(meta['all_count']).to eq(1)
  end

  it 'esperando_min fora do limite é ignorado' do
    expect(get_json('', esperando_min: '5000')['data']['meta']['all_count']).to eq(3)
  end
end
