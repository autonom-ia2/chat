require 'rails_helper'

RSpec.describe 'Autonomia quote choices', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) do
    Autonomia::Insurance::QuoteAgent::Builder.new(
      account: account, nome_agente: 'Lia', nome_corretora: 'Sena'
    ).call
  end
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/quote_choices" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  it 'updates choices through the agent endpoint and exposes only the safe quote DTO' do
    patch url,
          params: { name: 'Bia', behavior: 'objetivo', horario: 'das 8h às 18h' },
          headers: administrator.create_new_auth_token,
          as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('instrucao_mantida' => true)
    expect(response.parsed_body.fetch('quote_choices')).to eq(
      'name' => 'Bia', 'behavior' => 'objetivo', 'horario' => 'das 8h às 18h'
    )
    expect(response.body).not_to include('nome_corretora', 'Sena')
  end

  it 'rejects an invalid behavior without returning the submitted value' do
    patch url, params: { behavior: 'inventado' }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'quote_choices_invalid', 'key' => 'behavior')
    expect(response.body).not_to include('inventado')
  end

  it 'rejects unknown fields instead of silently dropping them' do
    patch url, params: { broker_name: 'Sena 2' }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'quote_choices_invalid', 'key' => 'broker_name')
  end

  it 'routes the generic quote name update through the same choices writer' do
    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          params: { agent: { name: 'Bia' } }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(agent.reload.config.fetch(Autonomia::Insurance::QuoteAgent::Builder::ESCOLHAS_DA_CORRETORA))
      .to include('nome_agente' => 'Bia', 'nome_corretora' => 'Sena')
  end

  it 'returns a validation error for an invalid generic quote name' do
    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          params: { agent: { name: '   ' } }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'quote_choices_invalid', 'key' => 'name')
  end
end
