require 'rails_helper'

# POST automation_rules/:id/ensaio (#859): o "Testar com casos reais" da tela Automações.
RSpec.describe 'Ensaio de automação', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:rule) do
    create(:automation_rule, account: account, active: false, event_name: 'conversation_created',
                             conditions: [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to',
                                            'values' => ['open'], 'query_operator' => nil }],
                             actions: [{ 'action_name' => 'resolve_conversation', 'action_params' => [] }])
  end
  let!(:conversa) { create(:conversation, account: account, inbox: inbox, status: :open) }

  def ensaiar(user, regra = rule, params = {})
    post "/api/v1/accounts/#{account.id}/automation_rules/#{regra.id}/ensaio",
         params: params, headers: user.create_new_auth_token, as: :json
  end

  it 'devolve o que a regra faria e não faz', :aggregate_failures do
    ensaiar(admin, rule, { quantidade: 5 })

    expect(response).to have_http_status(:ok)
    item = response.parsed_body['resultados'].first
    expect(item).to include('conversation_id' => conversa.id, 'casou' => true, 'faria' => ['resolve_conversation'])
    expect(conversa.reload.status).to eq('open')
    expect(rule.reload.active).to be(false)
  end

  it 'recusa agente sem permissão de automação' do
    ensaiar(create(:user, account: account, role: :agent))

    expect(response).to have_http_status(:unauthorized)
  end

  it 'responde 404 para regra de outra conta' do
    outra = create(:automation_rule, account: create(:account))

    ensaiar(admin, outra)

    expect(response).to have_http_status(:not_found)
  end

  it 'explica quando a regra tem condição inválida', :aggregate_failures do
    # A validação recusaria a condição; é justamente a regra quebrada que se quer ensaiar.
    quebrada = [{ 'attribute_key' => 'nao_existe', 'filter_operator' => 'equal_to', 'values' => ['x'], 'query_operator' => nil }]
    rule.update_column(:conditions, quebrada) # rubocop:disable Rails/SkipsModelValidations

    ensaiar(admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to be_present
  end
end
