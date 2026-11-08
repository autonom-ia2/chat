# CRM › Números por papel (#1897, F3 do #1871). Atrás da flag da conta (`crm_numeros_lentes`, 404 desligada) e da
# Crm::NumerosPolicy.
#
#   GET numeros?mes=AAAA-MM               a visão "Só eu" de quem abre (mês vazio = o de hoje, no fuso da conta)
#   GET numeros?mes=AAAA-MM&visao=equipe  a visão "Equipe" (#1992, F5), com a flag `crm_numeros_equipe`
#
# `visoes` diz o que a pessoa pode ver: "eu" e/ou "equipe". Sem a `crm_numeros_equipe`, a "Equipe" é o painel de hoje
# (crm/reports), e quem só vê a equipe recebe só `visoes`. Com ela, quem vê a equipe recebe os números da equipe quando
# pede `visao=equipe` ou quando só vê a equipe. Mês inválido = 422 `crm.numeros.mes_invalido`.
class Api::V1::Accounts::Crm::NumerosController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_numeros_enabled
  before_action :authorize_numeros

  rescue_from ::Crm::Numeros::Mes::Invalido do
    render_unprocessable('crm.numeros.mes_invalido')
  end

  def show
    mes = ::Crm::Numeros::Mes.new(account: Current.account, chave: params[:mes])
    return render json: equipe(mes) if equipe_nova?
    return render json: { visoes: visoes, visao: 'equipe', mes: mes.info } unless policy.eu?

    corpo = ::Crm::Numeros::SoEu.new(account: Current.account, user: Current.user, mes: mes, acesso: acesso,
                                     valor_da_equipe: valor_de_venda?).perform
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

  def equipe_nova?
    policy.equipe? && ::Crm::Config.numeros_equipe_enabled?(Current.account) && (params[:visao] == 'equipe' || !policy.eu?)
  end

  # O papel "dono" na tela é o administrador. O custo da IA é dinheiro da conta: segue `financial_view`, como o resto do
  # uso de IA (#1982), ou seja, administrador ou Financeiro. Quem vê a equipe sem trabalhar no CRM vê sem os botões.
  def equipe(mes)
    corpo = ::Crm::Numeros::Equipe.new(account: Current.account, user: Current.user, mes: mes, acesso: acesso,
                                       perfil: perfil_da_equipe).perform
    corpo.merge(visoes: visoes, visao: 'equipe', podeCriarFunil: pode_criar_funil?)
  end

  # valor: o R$ das vendas da equipe segue `sales_value_view` (#2075); sem ela, a Equipe mostra as contagens.
  def perfil_da_equipe
    conta = Current.account_user
    { dono: conta&.administrator? || false, custo: conta&.permission_granted?('financial_view') || false, leitura: !policy.eu?,
      valor: valor_de_venda? }
  end

  def valor_de_venda?
    ::Crm::ValorDeVenda.ve?(Current.account_user)
  end

  def pode_criar_funil?
    ::Crm::PipelinePolicy.new(pundit_user, ::Crm::Pipeline).create?
  end

  def acesso
    ::Crm::Access::VisiblePipelines.new(user: Current.user, account: Current.account, account_user: Current.account_user)
  end
end
