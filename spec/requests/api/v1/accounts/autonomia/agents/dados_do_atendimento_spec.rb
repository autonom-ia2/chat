require 'rails_helper'

# #1479 / #2723 — o bloco "Endereço e telefone" da página do agente salva pela API do agente (`config.atendimento`).
# Telefone inválido: 422 com a mensagem leiga. Salvar mescla: nunca apaga a outra chave do config.
RSpec.describe 'Autonomia agent dados do atendimento', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', instruction: 'Atenda.',
                                     config: { 'handoff_strategy' => 'none' })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def salvar(config, user: administrator)
    patch url, params: { agent: { config: config } }, headers: user.create_new_auth_token, as: :json
  end

  it 'salva, devolve e mescla com o resto do config' do
    salvar({ atendimento: { endereco: ' Rua das Flores, 120 ', telefone: '+5511940001234' } })

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('config', 'atendimento')).to eq('endereco' => 'Rua das Flores, 120',
                                                                    'telefone' => '+5511940001234')
    expect(agent.reload.config).to include('handoff_strategy' => 'none')
  end

  it 'salvar outra chave não apaga o atendimento' do
    salvar({ atendimento: { endereco: 'Rua das Flores, 120', telefone: '' } })

    salvar({ response_window: 'always' })

    expect(response).to have_http_status(:success)
    expect(agent.reload.config['atendimento']).to eq('endereco' => 'Rua das Flores, 120', 'telefone' => '')
    expect(agent.config['response_window']).to eq('always')
  end

  it 'telefone inválido: 422 com a mensagem leiga, nada gravado' do
    salvar({ atendimento: { endereco: 'Rua das Flores, 120', telefone: '+55 11' } })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to eq(I18n.t('autonomia.agents.atendimento.telefone_invalido'))
    expect(agent.reload.config).not_to have_key('atendimento')
  end

  it 'na criação, a mesma validação' do
    post "/api/v1/accounts/#{account.id}/autonomia/agents",
         params: { agent: { name: 'Bia', agent_type: 'custom', mode: 'guided',
                            config: { atendimento: { endereco: '', telefone: '1234' } } } },
         headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to eq(I18n.t('autonomia.agents.atendimento.telefone_invalido'))
    expect(Autonomia::Agents::Agent.where(account: account, name: 'Bia')).not_to exist
  end

  it 'quem só vê agentes não salva' do
    leitor = create(:user, account: account, role: :agent)
    leitor.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account,
                                                                                             permissions: ['autonomia_view']))

    salvar({ atendimento: { endereco: 'Rua das Flores, 120', telefone: '' } }, user: leitor)

    expect(response).not_to have_http_status(:success)
    expect(agent.reload.config).not_to have_key('atendimento')
  end
end
