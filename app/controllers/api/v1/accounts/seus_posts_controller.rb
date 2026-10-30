# Seus posts (#2302, F1 #2304): GET seus_posts?perfil=<id>&days=7|30|90. Atrás da flag da conta `seus_posts` (404
# desligada). Administrador ou `posts_view` (SeusPostsPolicy). Sem `perfil`, o primeiro perfil da conta. Período fora
# de 7, 30 e 90: 422. Perfil que não é da conta: 404. Meta fora do ar no perfil escolhido: o perfil vem
# `unavailable` (a tela mostra "Tentar de novo"). O que vem: SeusPosts::Leitura.
class Api::V1::Accounts::SeusPostsController < Api::V1::Accounts::BaseController
  before_action :ensure_seus_posts_enabled
  before_action :ensure_allowed

  def index
    # `days[]=1` chega como Array: to_s antes do to_i, e só 7, 30 ou 90 passam.
    days = params[:days].to_s.to_i
    return render json: { error: 'invalid_period' }, status: :unprocessable_entity unless SeusPosts::Leitura::DIAS.include?(days)

    leitura = SeusPosts::Leitura.new(account: Current.account, perfil: params[:perfil].presence, days: days, viewer: pundit_user)
    render json: leitura.perform
  rescue SeusPosts::Leitura::PerfilDesconhecido
    render json: { error: 'not_found' }, status: :not_found
  end

  private

  def ensure_seus_posts_enabled
    render json: { error: 'not_found' }, status: :not_found unless Current.account.feature_enabled?('seus_posts')
  end

  def ensure_allowed
    return if Pundit.policy!(pundit_user, :seus_posts).index?

    render json: { error: 'forbidden' }, status: :forbidden
  end
end
