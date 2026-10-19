# #1872 — a IA do cliente no editor de e-mail: o mesmo copiloto da conversa
# (Autonomia::Copilot::ConversationCopilot, chave da conta pelo crm_kanban_ai, consumo na Gestão IA),
# para reescrever só o texto, sem conversa (o e-mail novo da gaveta Escrever). Qualquer membro da
# conta usa, como o copiloto da conversa; os mesmos gates. O `status` diz à tela se o ✨ aparece.
class Api::V1::Accounts::Autonomia::TextCopilotController < Api::V1::Accounts::BaseController
  include DeferInteractiveAi
  include LimiteDoCopiloto

  # O pedido livre embaixo da sugestão é curto; o texto segue o teto do servidor (MAX_QUERY_CHARS).
  MAX_INSTRUCTION_CHARS = 1_000

  before_action :ensure_copilot_enabled, only: :create

  def status
    render json: { available: copilot_enabled? && ::Crm::Ai::Config.enabled? && credential_configured? }
  end

  def create
    error = validation_error
    return render_error(error) if error
    # Depois das validações: pedido recusado (422) não gasta a cota.
    return if limitar_copiloto!

    defer_interactive_ai('copilot_text', {
                           task: params[:task].to_s, draft: params[:draft].to_s,
                           tone: params[:tone].to_s.presence, instruction: params[:instruction].to_s.presence
                         })
  end

  private

  def ensure_copilot_enabled
    head :not_found unless copilot_enabled?
  end

  # Igual ao ConversationCopilotController: env desligado = tudo desligado (tela e endpoint).
  def copilot_enabled?
    ::Crm::Config.enabled? &&
      ::Autonomia::Agents::Config.enabled?(Current.account) &&
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('CRM_COPILOT_ENABLED', false))
  end

  def credential_configured?
    ::Crm::Ai::CredentialResolver.new(account: Current.account).configured?
  end

  # Recusa antes de enfileirar (o serviço cortaria o texto em silêncio). nil = pode ir.
  def validation_error
    task = params[:task].to_s
    return 'task_invalid' unless ::Autonomia::Copilot::ConversationCopilot::TASKS.include?(task)
    return 'task_needs_conversation' unless ::Autonomia::Copilot::ConversationCopilot::TEXT_TASKS.include?(task)
    return 'draft_missing' if params[:draft].to_s.strip.blank?
    return 'text_too_long' if params[:draft].to_s.length > ::Autonomia::Agents::Config::MAX_QUERY_CHARS

    'instruction_too_long' if params[:instruction].to_s.length > MAX_INSTRUCTION_CHARS
  end

  def render_error(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
