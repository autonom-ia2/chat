require 'rails_helper'

# O fuso da conta mora em dois campos (#954): custom_attributes['timezone'], que as telas e o Guia
# gravam, e settings['reporting_timezone'], que relatórios, CRM, caixas e SLA leem. Quem grava um
# leva o outro junto — e o Guia recebe o fuso para marcar o horário de quem pediu.
RSpec.describe 'Fuso da conta', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  def gravar(params)
    patch "/api/v1/accounts/#{account.id}", params: params, headers: admin.create_new_auth_token, as: :json
  end

  it 'gravar o fuso nas configurações leva os dois campos para o mesmo fuso', :aggregate_failures do
    gravar(timezone: 'America/Cuiaba')

    expect(response).to have_http_status(:success)
    expect(account.reload.custom_attributes['timezone']).to eq('America/Cuiaba')
    expect(account.reporting_timezone).to eq('America/Cuiaba')
  end

  it 'um fuso que não existe é recusado e nada muda', :aggregate_failures do
    account.update!(custom_attributes: { 'timezone' => 'America/Sao_Paulo' })

    gravar(timezone: 'America/Atlantida')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.custom_attributes['timezone']).to eq('America/Sao_Paulo')
    expect(account.reporting_timezone).to eq('America/Sao_Paulo')
  end

  it 'Primeiros passos também leva os dois campos', :aggregate_failures do
    account.update!(custom_attributes: { 'onboarding_step' => 'account_details' })

    patch "/api/v1/accounts/#{account.id}/onboarding",
          params: { onboarding_step: 'account_details', name: 'Corretora', locale: 'pt_BR', timezone: 'America/Rio_Branco' },
          headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(account.reload.custom_attributes['timezone']).to eq('America/Rio_Branco')
    expect(account.reporting_timezone).to eq('America/Rio_Branco')
  end

  it 'o Guia recebe o fuso da conta junto com a tela' do
    account.update!(custom_attributes: { 'timezone' => 'America/Cuiaba' })
    allow(Autonomia::Guide::Seed).to receive_messages(eligible?: true, ready_agent_for: instance_double(Autonomia::Agents::Agent))
    allow(Autonomia::Agents::Retriever).to receive(:new).and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
    query = nil
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      query = kwargs[:query]
      instance_double(Autonomia::Agents::Answerer,
                      answer: Autonomia::Agents::AnswerResult.new(reply: 'ok', confidence: 1.0, handoff: { should: false }))
    end

    perform_enqueued_jobs(only: Autonomia::Guide::ChatJob) do
      post "/api/v1/accounts/#{account.id}/autonomia/guide/chat",
           params: { message: 'me lembra amanhã às 9h', route_context: 'crm_kanban_index' },
           headers: admin.create_new_auth_token, as: :json
    end

    expect(query).to include('Tela atual: crm_kanban_index. Fuso da conta: America/Cuiaba.')
  end
end
