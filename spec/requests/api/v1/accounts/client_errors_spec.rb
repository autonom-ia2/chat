require 'rails_helper'

# #1841: browser errors land as one `[client_error]` line in our own log, no external service.
RSpec.describe 'Client errors API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/client_errors" }
  let(:lines) { [] }

  before do
    allow(Rails.logger).to receive(:error).and_call_original
    allow(Rails.logger).to receive(:error).with(a_string_starting_with('[client_error]')) { |line| lines << line }
  end

  def logged
    JSON.parse(lines.sole.delete_prefix('[client_error] '))
  end

  it 'writes one line with the account, the user and what the panel sent' do
    post path, params: { flow: 'email_builder_save', status: 500, message: 'Request failed', stack: 'at save' },
               headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(logged).to include('account_id' => account.id, 'user_id' => agent.id, 'flow' => 'email_builder_save',
                              'status' => 500, 'message' => 'Request failed', 'stack' => 'at save')
  end

  it 'cuts a long message and stack' do
    post path, params: { flow: 'email_builder_save', message: 'm' * 900, stack: 's' * 9000 },
               headers: agent.create_new_auth_token, as: :json

    expect(logged['message'].length).to eq(500)
    expect(logged['stack'].length).to eq(4000)
    expect(logged['status']).to be_nil
  end

  it 'keeps only a real HTTP status and only text in the text fields, without failing' do
    [[[1], nil], [{ a: 1 }, nil], ['abc', nil], ['99999999999999999999', nil], ['503', 503], [404, 404]].each do |sent, kept|
      lines.clear
      post path, params: { flow: 'email_builder_save', status: sent, message: ['x'], stack: { a: 1 } },
                 headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(logged).to include('status' => kept, 'message' => '', 'stack' => '')
    end
  end

  it 'refuses a flow that is not text' do
    post path, params: { flow: ['email_builder_save'] }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(lines).to be_empty
  end

  it 'stays out of the Guia: no catalog action, no format' do
    acoes = Autonomia::Guide::Acoes.new(account: account, user: agent)

    expect(acoes.catalogo).not_to include('POST client_errors')
    expect(Autonomia::Guide::Formatos::RotasDeEscrita.todas.map(&:acao)).not_to include('POST client_errors')
  end

  it 'refuses a missing or oversized flow without logging' do
    post path, params: { flow: ' ' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post path, params: { flow: 'f' * 65 }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lines).to be_empty
  end

  it 'refuses someone outside the account' do
    outsider = create(:user)

    post path, params: { flow: 'email_builder_save' }, headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(lines).to be_empty
  end

  it 'refuses an anonymous call' do
    post path, params: { flow: 'email_builder_save' }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(lines).to be_empty
  end
end
