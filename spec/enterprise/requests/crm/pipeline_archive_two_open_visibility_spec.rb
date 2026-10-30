require 'rails_helper'

# Arquivar funil com Mover (#2145): o resumo dos clientes que ficaram com mais de um card aberto no destino. Quem
# gerencia funis com função personalizada e caixa restrita só recebe o nome do cliente cujo card ele vê no CRM; o total
# conta todos. Achado da sessão Funções.
RSpec.describe 'Arquivar funil: resumo dos dois abertos com função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:caixa_dele) { create_crm_inbox(account: account, name: 'Dele', members: [agent, admin]) }
  let(:outra_caixa) { create_crm_inbox(account: account, name: 'Outra', members: [admin]) }
  let(:funil) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:destino) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/pipelines" }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  before do
    role = create(:custom_role, account: account, permissions: %w[crm_view crm_manage_pipelines conversation_participating_manage])
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  # Cliente com um card no destino e outro no funil que vai ser arquivado, os dois na mesma caixa. Devolve o que move.
  def cliente_com_dois(nome, caixa)
    contato = account.contacts.create!(name: nome)
    account.crm_cards.create!(pipeline: destino.first, stage: destino.last, inbox: caixa, contact: contato, title: "#{nome} no destino")
    account.crm_cards.create!(pipeline: funil.first, stage: funil.last, inbox: caixa, contact: contato, title: nome)
  end

  def arquivar_como(user)
    delete "#{base}/#{funil.first.id}", params: { move_to_stage_id: destino.last.id }, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body.dig('payload', 'clients_with_two_open')
  end

  it 'função com caixa restrita: o total conta todos, os nomes só de quem ela vê' do
    da_ana = cliente_com_dois('Ana', caixa_dele)
    cliente_com_dois('Bia', outra_caixa)

    resumo = arquivar_como(agent)

    expect(resumo['count']).to eq(2)
    expect(resumo['items']).to eq([{ 'contact_id' => da_ana.contact_id, 'name' => 'Ana', 'card_id' => da_ana.id }])
  end

  it 'administrador recebe todos os nomes' do
    da_ana = cliente_com_dois('Ana', caixa_dele)
    da_bia = cliente_com_dois('Bia', outra_caixa)

    resumo = arquivar_como(admin)

    expect(resumo['count']).to eq(2)
    expect(resumo['items'].pluck('card_id')).to contain_exactly(da_ana.id, da_bia.id)
  end
end
