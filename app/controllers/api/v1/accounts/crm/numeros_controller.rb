# CRM › Números por papel (#1897, F3 do #1871). Atrás da flag da conta (`crm_numeros_lentes`, 404 desligada) e da
# Crm::NumerosPolicy.
#
#   GET numeros?mes=AAAA-MM   a visão "Só eu" de quem abre (mês vazio = o de hoje, no fuso da conta)
#
# `visoes` diz o que a pessoa pode ver: "eu" e/ou "equipe". Até a F5, a "Equipe" é o painel de hoje (crm/reports), e
# quem só vê a equipe recebe só `visoes`. Mês inválido = 422 `crm.numeros.mes_invalido`.
class Api::V1::Accounts::Crm::NumerosController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_numeros_enabled
  before_action :authorize_numeros

  rescue_from ::Crm::Numeros::Mes::Invalido do
    render_unprocessable('crm.numeros.mes_invalido')
  end

  def show
    mes = ::Crm::Numeros::Mes.new(account: Current.account, chave: params[:mes])
    return render json: { visoes: visoes, visao: 'equipe', mes: mes.info } unless policy.eu?

    corpo = ::Crm::Numeros::SoEu.new(account: Current.account, user: Current.user, mes: mes, acesso: acesso).perform
    render json: corpo.merge(visoes: visoes, visao: 'eu', podeCriarFunil: pode_criar_funil?)
  end

  private

  def ensure_numeros_enabled
    render json: { error: 'crm.numeros.disabled' }, status: :not_found unless ::Crm::Config.numeros_lentes_enabled?(Current.account)
  end

  def authorize_numeros
    authorize :numeros, :show?, policy_class: ::Crm::NumerosPolicy
  end

  def policy
    @policy ||= ::Crm::NumerosPolicy.new(pundit_user, :numeros)
  end

  def visoes
    [('eu' if policy.eu?), ('equipe' if policy.equipe?)].compact
  end

  def pode_criar_funil?
    ::Crm::PipelinePolicy.new(pundit_user, ::Crm::Pipeline).create?
  end

  def acesso
    ::Crm::Access::VisiblePipelines.new(user: Current.user, account: Current.account, account_user: Current.account_user)
  end
end
