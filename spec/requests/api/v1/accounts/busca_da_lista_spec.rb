require 'rails_helper'

# #2211 — a porta da busca da lista: pede login, e devolve as três seções e o telefone novo no formato que a lista usa.
RSpec.describe 'Busca da lista de conversas', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/busca_da_lista" }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    joao = create(:contact, account: account, name: 'João Prado', phone_number: '+5511978622068')
    conversa = create(:conversation, account: account, inbox: inbox, contact: joao)
    create(:message, account: account, inbox: inbox, conversation: conversa, content: 'O João pediu a cotação')
    create(:contact, account: account, name: 'Joana Sem Conversa')
  end

  it 'pede login' do
    get url, params: { q: 'joao' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve conversas no formato da lista, mensagens e pessoas sem conversa' do
    get url, params: { q: 'joa' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    payload = response.parsed_body['payload']
    expect(payload['conversations'].pluck('meta').map { |meta| meta['sender']['name'] }).to eq(['João Prado'])
    expect(payload['conversations'].first).to include('waiting_since', 'last_non_activity_message', 'status')
    expect(payload['messages'].first).to include('content' => 'O João pediu a cotação', 'conversation_id' => kind_of(Integer))
    expect(payload['contacts'].pluck('name')).to eq(['Joana Sem Conversa'])
    expect(payload['telefone_novo']).to be_nil
    expect(payload['parcial']).to eq([])
  end

  it 'com um telefone que ninguém tem, oferece o número' do
    get url, params: { q: '21 99999-0000' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']['telefone_novo']).to eq('+5521999990000')
  end
end
