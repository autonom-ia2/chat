# CRM › Números › "De onde vieram os clientes" (#2001, F6 do #1871). Atrás da flag da conta `crm_numeros_origens`
# (404 desligada) e da régua da visão "Equipe" (Crm::NumerosPolicy#equipe?: administrador e `crm_view_reports`).
#
#   GET numeros/origens?mes=AAAA-MM&funil=<id>|todos                       a tela (Crm::Numeros::Origens::Tela)
#   GET numeros/origens/report?formato=pdf|planilha&mes=AAAA-MM&funil=…    o relatório baixado, com os mesmos números
#
# Mês inválido: 422 `crm.numeros.mes_invalido`. Funil que a pessoa não vê: 403.
# Gasto: só para quem pode ver os anúncios (Crm::MetaAdsConnectionPolicy#show?). R$ de venda: `sales_value_view`
# (Crm::ValorDeVenda, #2075). No arquivo, a lista de clientes vai só para quem pode exportar o CRM
# (Crm::CardPolicy#export?, crm_export: dado pessoal em lote) e só com os cards que a pessoa vê (policy_scope).
class Api::V1::Accounts::Crm::NumerosOrigensController < Api::V1::Accounts::Crm::BaseController
  FORMATOS = {
    'pdf' => [::Crm::Numeros::Origens::Relatorio::Pdf, 'application/pdf'],
    'planilha' => [::Crm::Numeros::Origens::Relatorio::Planilha, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
  }.freeze

  before_action :ensure_origens_enabled
  before_action :authorize_equipe

  rescue_from ::Crm::Numeros::Mes::Invalido do
    render_unprocessable('crm.numeros.mes_invalido')
  end

  rescue_from ::Crm::Numeros::Origens::Funis::ForaDoAcesso do
    render json: { error: 'crm.numeros.funil_fora_do_acesso' }, status: :forbidden
  end

  def show
    render json: tela.perform
  end

  def report
    klass, content_type = FORMATOS[params[:formato].to_s]
    return render_unprocessable('invalid_format') if klass.nil?

    dados = ::Crm::Numeros::Origens::Relatorio::Dados.new(tela, account: Current.account, cards_visiveis: cards_visiveis)
    arquivo = klass.new(dados)
    send_data arquivo.gerar, filename: arquivo.nome, type: content_type, disposition: :attachment
  end

  private

  def ensure_origens_enabled
    render json: { error: 'crm.numeros.disabled' }, status: :not_found unless ::Crm::Config.numeros_origens_enabled?(Current.account)
  end

  def authorize_equipe
    authorize :numeros, :equipe?, policy_class: ::Crm::NumerosPolicy
  end

  def tela
    @tela ||= ::Crm::Numeros::Origens::Tela.new(account: Current.account, mes: mes, funis: funis, perfil: perfil)
  end

  def mes
    ::Crm::Numeros::Mes.new(account: Current.account, chave: params[:mes])
  end

  def funis
    acesso = ::Crm::Access::VisiblePipelines.new(user: Current.user, account: Current.account, account_user: Current.account_user)
    ::Crm::Numeros::Origens::Funis.new(account: Current.account, acesso: acesso, pedido: params[:funil])
  end

  def perfil
    { gasto: Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).show?, valor: ::Crm::ValorDeVenda.ve?(Current.account_user) }
  end

  # Sem a permissão de exportar o CRM, nenhuma pessoa vai no arquivo (nil).
  def cards_visiveis
    policy_scope(::Crm::Card) if Pundit.policy!(pundit_user, ::Crm::Card).export?
  end
end
