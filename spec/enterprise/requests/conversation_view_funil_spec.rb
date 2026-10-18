require 'rails_helper'

# #1800 com o acesso por funil (#1148): conversation_view lê o que a pessoa alcança, e o alcance continua passando pelo
# Crm::Access::ConversationScope. Numa caixa com funil restrito, quem só lê não vê conversa de outro funil (nem na
# lista, nem pelo link) e, como não opera, não manda convite de agendamento.
RSpec.describe 'conversation_view com acesso por funil', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:leitora) do
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: %w[conversation_view])
    user.account_users.find_by(account: account).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: inbox)
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
    access.agent_pipelines.create!(account: account, pipeline: vendas.first)
    user
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true',
                      'FRONTEND_URL' => 'https://app.example.com') { example.run }
  end

  def conversa_no_funil(pipeline_and_stage, titulo)
    contato = create(:contact, account: account)
    conversa = create(:conversation, account: account, inbox: inbox, contact: contato)
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, title: titulo, contact: contato,
                              inbox: inbox, primary_conversation: conversa)
    conversa
  end

  def ids_da_lista(user)
    get "#{base}/conversations", params: { status: 'all', assignee_type: 'all' }, headers: user.create_new_auth_token, as: :json
    response.parsed_body.dig('data', 'payload').pluck('id')
  end

  it 'lê só a conversa do funil dela, na lista e pelo link' do
    da_venda = conversa_no_funil(vendas, 'Venda')
    do_sinistro = conversa_no_funil(sinistro, 'Sinistro')
    auth = leitora.create_new_auth_token

    expect(ids_da_lista(leitora)).to eq([da_venda.display_id])

    get "#{base}/conversations/#{da_venda.display_id}/messages", headers: auth, as: :json
    expect(response).to have_http_status(:success)

    get "#{base}/conversations/#{do_sinistro.display_id}", headers: auth, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/conversations/#{do_sinistro.display_id}/messages", headers: auth, as: :json
    expect(response).to have_http_status(:unauthorized)

    expect(ids_da_lista(admin)).to contain_exactly(da_venda.display_id, do_sinistro.display_id)
  end

  it 'não manda convite de agendamento pela conversa que lê' do
    account.enable_features('crm_booking_v2')
    account.save!
    world
    da_venda = conversa_no_funil(vendas, 'Venda')

    expect do
      post "#{base}/crm/booking_invites", params: { conversation_id: da_venda.display_id }, headers: leitora.create_new_auth_token, as: :json
    end.not_to change(Crm::BookingInvite, :count)
    expect(response).to have_http_status(:unauthorized)
  end
end
