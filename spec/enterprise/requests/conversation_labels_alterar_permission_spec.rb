require 'rails_helper'

# #2202 (PR 3) — pôr e tirar etiquetas uma a uma (labels/alterar) segue a regra da rota de sempre (labels#create):
# quem opera a conversa pode; quem só lê (conversation_view) não. Com função personalizada, vale o trio conversation_*.
RSpec.describe 'Pôr e tirar etiqueta da conversa com função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:alheia) { create(:conversation, account: account, inbox: inbox) }
  let(:dela) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    [alheia, dela].each { |conversa| conversa.update_labels(['vip']) }
  end

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def alterar(conversa)
    patch "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/labels/alterar",
          params: { por: ['boleto'] }, headers: agent.create_new_auth_token, as: :json
  end

  it 'conversation_manage põe etiqueta em qualquer conversa que alcança' do
    give_role(%w[conversation_manage])
    alterar(alheia)

    expect(response).to have_http_status(:ok)
    expect(alheia.reload.label_list).to contain_exactly('vip', 'boleto')
  end

  it 'conversation_participating_manage põe só na conversa que atende' do
    give_role(%w[conversation_participating_manage])

    alterar(dela)
    expect(response).to have_http_status(:ok)
    expect(dela.reload.label_list).to contain_exactly('vip', 'boleto')

    alterar(alheia)
    expect(response).to have_http_status(:unauthorized)
    expect(alheia.reload.label_list).to eq(['vip'])
  end

  it 'conversation_unassigned_manage põe na conversa sem dono e na dela' do
    give_role(%w[conversation_unassigned_manage])

    alterar(alheia)
    expect(response).to have_http_status(:ok)
    expect(alheia.reload.label_list).to contain_exactly('vip', 'boleto')
  end

  it 'quem só lê (conversation_view) não põe nem tira' do
    give_role(%w[conversation_view])

    alterar(dela)
    expect(response).to have_http_status(:unauthorized)
    expect(dela.reload.label_list).to eq(['vip'])
  end
end
