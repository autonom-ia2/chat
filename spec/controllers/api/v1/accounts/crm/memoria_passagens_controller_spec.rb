require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Crm::MemoriaPassagens', type: :request do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, name: 'Ana', role: :administrator) }
  let(:caminho) { "/api/v1/accounts/#{account.id}/crm/memoria/conversations/#{conversation.display_id}/passagem" }

  before { ligar_memoria!(account) }

  it 'devolve a última passagem com o bilhete e a tarefa aberta' do
    passagem = Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')
    Crm::Memoria::PassagemJob.perform_now(passagem.id)

    get caminho, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    corpo = response.parsed_body
    expect(corpo['passagem']).to include('id' => passagem.id, 'bilhete_status' => 'fallback', 'para_nome' => 'Ana')
    expect(corpo['tarefa']).to include('origem' => 'passagem', 'confirmar' => false)
  end

  it 'conversa de outra conta é 404' do
    de_fora = create(:conversation)

    get "/api/v1/accounts/#{account.id}/crm/memoria/conversations/#{de_fora.display_id + 1000}/passagem",
        headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
