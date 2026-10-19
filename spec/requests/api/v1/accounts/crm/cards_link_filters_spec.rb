require 'rails_helper'

# #1883: os links do Números abrem a Lista já filtrada. "Ganhos do mês" usa o mês no fuso da conta.
RSpec.describe 'CRM cards list filters from Números links', type: :request do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }

  it 'lists only the cards won this month in the account time zone' do
    account.update!(reporting_timezone: 'America/Sao_Paulo')
    pipeline, stage = create_crm_pipeline(account: account, user: user)

    won_at = ->(time, title) { travel_to(time) { account.crm_cards.create!(pipeline: pipeline, stage: stage, title: title, status: :won) } }
    november = won_at.call(Time.utc(2026, 11, 1, 3, 30), 'Novembro')
    won_at.call(Time.utc(2026, 11, 1, 2, 30), 'Outubro no fuso')

    travel_to Time.utc(2026, 11, 10, 12) do
      get "/api/v1/accounts/#{account.id}/crm/cards",
          params: { pipeline_id: pipeline.id, result: 'won', closed_in: 'this_month' },
          headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(november.id)
    end
  end
end
