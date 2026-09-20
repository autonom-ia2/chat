class Api::V1::Accounts::OnboardingProgressController < Api::V1::Accounts::BaseController
  # Só leitura do estado da própria conta: qualquer membro pode ver a trilha
  # dele. Administrador vê a trilha inteira; agente vê apenas os passos do
  # trabalho dele (perfil e primeira resposta), pelo filtro por perfil.
  def index
    render json: { passos: progresso.perform }
  end

  def skip
    render json: { passo: progresso.pular(params[:id]), status: 'pulado' }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def resume
    render json: { passo: progresso.retomar(params[:id]), status: 'pendente' }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def progresso
    @progresso ||= Onboarding::Progress.new(
      account: Current.account,
      user: Current.user,
      perfil: Current.account_user&.role || 'agent'
    )
  end
end
