require 'rails_helper'

RSpec.describe 'CRM calendar API', type: :request do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CRM_KANBAN_ENABLED')
    else
      ENV['CRM_KANBAN_ENABLED'] = previous_value
    end
  end

  it 'returns follow-ups and expected closes scoped to the selected pipeline' do
    account, user = create_account_and_user
    first_pipeline, first_stage = create_crm_pipeline(account: account, user: user, name: 'Vendas')
    second_pipeline, second_stage = create_crm_pipeline(account: account, user: user, name: 'Suporte')
    first_card = account.crm_cards.create!(
      pipeline: first_pipeline,
      stage: first_stage,
      title: 'Lead Vendas',
      expected_close_at: 2.days.from_now
    )
    second_card = account.crm_cards.create!(
      pipeline: second_pipeline,
      stage: second_stage,
      title: 'Lead Suporte',
      expected_close_at: 2.days.from_now
    )
    account.crm_follow_ups.create!(card: first_card, title: 'Retornar Vendas', due_at: 1.day.from_now, timezone: 'UTC', created_by: user)
    account.crm_follow_ups.create!(card: second_card, title: 'Retornar Suporte', due_at: 1.day.from_now, timezone: 'UTC', created_by: user)

    get "/api/v1/accounts/#{account.id}/crm/calendar/events",
        params: {
          pipeline_id: first_pipeline.id,
          from: 1.hour.ago.iso8601,
          to: 3.days.from_now.iso8601
        },
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    titles = response.parsed_body['payload'].map { |event| event['title'] }
    expect(titles).to include('Lead Vendas', 'Retornar Vendas')
    expect(titles).not_to include('Lead Suporte', 'Retornar Suporte')
  end

  # #1538: o vencimento é uma data (00:00 UTC). A janela do mês em São Paulo começa às 03:00 UTC do dia 1; o vencimento
  # do dia 1 precisa aparecer, e o do último dia do mês anterior não.
  it 'inclui o vencimento do primeiro dia da janela pedida no fuso de quem olha' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user, name: 'Cobrança')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Vence no dia 1', expected_close_at: '2026-10-01')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Venceu antes', expected_close_at: '2026-09-30')

    get "/api/v1/accounts/#{account.id}/crm/calendar/events",
        params: { pipeline_id: pipeline.id, from: '2026-10-01T00:00:00-03:00', to: '2026-10-31T23:59:59-03:00' },
        headers: auth_headers(user)

    titles = response.parsed_body['payload'].map { |event| event['title'] }
    expect(titles).to include('Vence no dia 1')
    expect(titles).not_to include('Venceu antes')
  end

  it 'filters follow-ups and expected closes by owner_id from the frontend filters' do
    account, admin = create_account_and_user
    first_owner, = create_crm_agent(account: account, name: 'Primeiro')
    second_owner, = create_crm_agent(account: account, name: 'Segundo')
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    first_card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      owner: first_owner,
      title: 'Lead Primeiro',
      expected_close_at: 2.days.from_now
    )
    second_card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      owner: second_owner,
      title: 'Lead Segundo',
      expected_close_at: 2.days.from_now
    )
    account.crm_follow_ups.create!(
      card: first_card,
      assignee: first_owner,
      title: 'Retornar Primeiro',
      due_at: 1.day.from_now,
      timezone: 'UTC',
      created_by: admin
    )
    account.crm_follow_ups.create!(
      card: second_card,
      assignee: second_owner,
      title: 'Retornar Segundo',
      due_at: 1.day.from_now,
      timezone: 'UTC',
      created_by: admin
    )

    get "/api/v1/accounts/#{account.id}/crm/calendar/events",
        params: {
          pipeline_id: pipeline.id,
          owner_id: first_owner.id,
          from: 1.hour.ago.iso8601,
          to: 3.days.from_now.iso8601
        },
        headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    titles = response.parsed_body['payload'].map { |event| event['title'] }
    expect(titles).to include('Lead Primeiro', 'Retornar Primeiro')
    expect(titles).not_to include('Lead Segundo', 'Retornar Segundo')
  end

  it 'handles invalid calendar filter params without server errors' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead Seguro',
      expected_close_at: 2.days.from_now
    )
    account.crm_follow_ups.create!(
      card: card,
      title: 'Retornar Seguro',
      due_at: 1.day.from_now,
      timezone: 'UTC',
      created_by: user
    )

    get "/api/v1/accounts/#{account.id}/crm/calendar/events",
        params: { pipeline_id: pipeline.id, from: 'data-invalida', to: '999999-01-01', limit: -20 },
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to be_an(Array)
  end
end
