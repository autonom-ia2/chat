class Api::V1::Accounts::AiRequestsController < Api::V1::Accounts::BaseController
  def show
    data = Crm::Ai::InteractiveRequest.read(params[:id])
    return head :not_found unless accessible_request?(data)

    operation = Crm::Ai::InteractiveOperation.new(data)
    operation.authorize!
    payload = { status: data['status'], result: data['result'] }
    test_payload = test_payload_for(operation, data)
    payload[:test] = test_payload if test_payload.present?
    render json: payload
  end

  private

  def accessible_request?(data)
    data && data['account_id'] == Current.account.id &&
      data['account_user_id'] == Current.account_user&.id &&
      data['integration_token_id'] == current_integration_token&.id
  end

  def test_payload_for(operation, data)
    return unless data['status'] == 'done' && data['result'].is_a?(Hash) && data['result'].present?

    test_agent = operation.test_agent
    return unless test_agent

    current_digest = Autonomia::Agents::TestDigest.for_agent(agent: test_agent)
    Autonomia::Agents::TestResultRecorder.public_payload(
      agent: test_agent,
      current_digests: {
        aggregate: current_digest.fetch(:tested_digest),
        person: current_digest.fetch(:person_digest),
        material: current_digest.fetch(:material_snapshot_digest)
      },
      material_snapshot_state: current_digest.fetch(:material_snapshot_state),
      session_id: data.dig('inputs', 'session_id')
    )
  end
end
