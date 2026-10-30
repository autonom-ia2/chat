require 'rails_helper'

# #2211 — a porta da busca da lista: pede login, e devolve as três seções, o telefone novo e o e-mail novo no formato que a lista usa.
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
    expect(payload).to include('telefone_novo' => nil, 'texto_livre_nas_caixas' => [], 'email_novo' => nil,
                               'caixas_para_comecar' => [], 'parcial' => [])
  end

  it 'com NUL no q, responde 200' do
    get url, params: { q: "jo\u0000ao" }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'com um telefone que ninguém tem, oferece o número' do
    get url, params: { q: '21 99999-0000' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']['telefone_novo']).to eq('+5521999990000')
    expect(response.parsed_body['payload']['email_novo']).to be_nil
  end

  it 'com um telefone novo, diz em quais caixas do WhatsApp Híbrido a primeira mensagem pode ser texto livre' do
    canal = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    create(:inbox_member, user: agent, inbox: canal.inbox)
    WhatsappHybrid::Connection.create!(account: account, inbox: canal.inbox, session_name: 'hibrida-request', status: 'connected',
                                       connected_phone: canal.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
                                       status_checked_at: Time.current)
    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) do
      get url, params: { q: '21 99999-0000' }, headers: agent.create_new_auth_token, as: :json
    end
    expect(response.parsed_body['payload']).to include('telefone_novo' => '+5521999990000', 'texto_livre_nas_caixas' => [canal.inbox.id])
  end

  # O create da conversa pede InboxPolicy#show?: a caixa que inbox_view mostra sem ser membro não vem (#2211).
  it 'com telefone ou e-mail novo, diz em quais caixas dá para começar conversa' do
    alheia = create(:inbox, account: account)
    funcao = create(:custom_role, account: account, permissions: %w[conversation_manage contact_manage inbox_view])
    agent.account_users.find_by!(account: account).update!(custom_role: funcao)
    admin = create(:user, account: account, role: :administrator)

    get url, params: { q: '21 99999-0000' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']['caixas_para_comecar']).to eq([inbox.id])
    get url, params: { q: 'nova@example.test' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']['caixas_para_comecar']).to eq([inbox.id])
    get url, params: { q: 'nova@example.test' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']['caixas_para_comecar']).to eq([inbox.id, alheia.id])
    get url, params: { q: 'joa' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']['caixas_para_comecar']).to eq([])
  end

  it 'com um e-mail que ninguém tem, oferece o e-mail em minúsculas' do
    get url, params: { q: ' Nova.Pessoa@Example.TEST ' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to include('email_novo' => 'nova.pessoa@example.test', 'telefone_novo' => nil)
  end
end
