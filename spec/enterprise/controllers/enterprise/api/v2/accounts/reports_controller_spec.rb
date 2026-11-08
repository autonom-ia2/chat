# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise Reports API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  # Create a custom role with report_manage permission
  let!(:custom_role) { create(:custom_role, account: account, permissions: ['report_manage']) }
  let!(:agent_with_role) { create(:user) }
  let(:agent_with_role_account_user) do
    create(:account_user, user: agent_with_role, account: account, role: :agent, custom_role: custom_role)
  end

  let(:default_timezone) { 'UTC' }
  let(:start_of_today) { Time.current.in_time_zone(default_timezone).beginning_of_day.to_i }
  let(:end_of_today) { Time.current.in_time_zone(default_timezone).end_of_day.to_i }
  let(:params) { { timezone_offset: Time.zone.utc_offset } }

  before do
    agent_with_role_account_user
  end

  describe 'GET /api/v2/accounts/:account_id/reports' do
    context 'when it is an authenticated user' do
      let(:params) do
        super().merge(
          metric: 'conversations_count',
          type: :account,
          since: start_of_today.to_s,
          until: end_of_today.to_s
        )
      end

      it 'returns success for agents with report_manage permission' do
        get "/api/v2/accounts/#{account.id}/reports",
            params: params,
            headers: agent_with_role.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/reports/summary' do
    context 'when it is an authenticated user' do
      let(:params) do
        super().merge(
          type: :account,
          since: start_of_today.to_s,
          until: end_of_today.to_s
        )
      end

      it 'returns success for agents with report_manage permission' do
        get "/api/v2/accounts/#{account.id}/reports/summary",
            params: params,
            headers: agent_with_role.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  # Report viewers open the drilldown, limited to the conversations they can see in the conversation list (#2123).
  describe 'GET /api/v2/accounts/:account_id/reports/drilldown' do
    let(:conversation_a) { create(:conversation, account: account, inbox: create(:inbox, account: account)) }
    let(:conversation_b) { create(:conversation, account: account, inbox: create(:inbox, account: account)) }
    let(:metric) { 'conversations_count' }
    let(:params) do
      super().merge(
        metric: metric,
        type: :account,
        since: start_of_today.to_s,
        until: end_of_today.to_s,
        bucket_timestamp: start_of_today.to_s,
        group_by: 'day'
      )
    end

    let(:viewer) { create(:user) }

    def drilldown_as(user)
      get "/api/v2/accounts/#{account.id}/reports/drilldown", params: params, headers: user.create_new_auth_token, as: :json
      response.parsed_body
    end

    def conversation_ids(body)
      body['payload'].map { |record| record['conversation']['id'] }
    end

    before do
      viewer_role = create(:custom_role, account: account, permissions: %w[report_manage conversation_manage])
      create(:account_user, user: viewer, account: account, role: :agent, custom_role: viewer_role)
      create(:inbox_member, user: viewer, inbox: conversation_a.inbox)
      conversation_a
      conversation_b
    end

    it 'lists every conversation for administrators' do
      admin = create(:user, account: account, role: :administrator)

      body = drilldown_as(admin)

      expect(response).to have_http_status(:success)
      expect(conversation_ids(body)).to contain_exactly(conversation_a.id, conversation_b.id)
      expect(body['meta']).to include('total_count' => 2, 'conversation_count' => 2)
    end

    it 'lists only the conversations of inboxes the report viewer belongs to' do
      body = drilldown_as(viewer)

      expect(response).to have_http_status(:success)
      expect(conversation_ids(body)).to eq([conversation_a.id])
      expect(body['meta']).to include('total_count' => 1, 'conversation_count' => 1)
    end

    context 'with a message metric' do
      let(:metric) { 'incoming_messages_count' }

      it 'lists only messages from conversations the report viewer can see' do
        create(:message, account: account, inbox: conversation_a.inbox, conversation: conversation_a, message_type: :incoming)
        create_list(:message, 2, account: account, inbox: conversation_b.inbox, conversation: conversation_b, message_type: :incoming)

        body = drilldown_as(viewer)

        expect(response).to have_http_status(:success)
        expect(conversation_ids(body)).to eq([conversation_a.id])
        expect(body['meta']).to include('record_type' => 'message', 'total_count' => 1, 'conversation_count' => 1)
      end
    end

    context 'with a reporting event metric' do
      let(:metric) { 'avg_first_response_time' }

      it 'lists only events from conversations the report viewer can see' do
        create(:reporting_event, account: account, inbox: conversation_a.inbox, conversation: conversation_a, name: 'first_response')
        create(:reporting_event, account: account, inbox: conversation_b.inbox, conversation: conversation_b, name: 'first_response')

        body = drilldown_as(viewer)

        expect(response).to have_http_status(:success)
        expect(conversation_ids(body)).to eq([conversation_a.id])
        expect(body['meta']).to include('total_count' => 1, 'conversation_count' => 1)
      end
    end

    it 'returns an empty list when the report viewer sees no conversation' do
      body = drilldown_as(agent_with_role)

      expect(response).to have_http_status(:success)
      expect(body['payload']).to be_empty
      expect(body['meta']).to include('total_count' => 0, 'conversation_count' => 0)
    end

    it 'keeps the drilldown closed for agents without report access' do
      create(:inbox_member, user: agent, inbox: conversation_a.inbox)

      drilldown_as(agent)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
