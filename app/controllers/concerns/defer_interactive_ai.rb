module DeferInteractiveAi
  private

  def defer_interactive_ai(operation, inputs)
    id = Crm::Ai::InteractiveRequest.create(
      account_user: Current.account_user, operation: operation,
      inputs: inputs, locale: I18n.locale.to_s, integration_token_id: current_integration_token&.id
    )
    Crm::Ai::InteractiveJob.perform_later(id)
    render json: { id: id, status: 'pending', poll_url: "/api/v1/accounts/#{Current.account.id}/ai_requests/#{id}" }, status: :accepted
  end
end
