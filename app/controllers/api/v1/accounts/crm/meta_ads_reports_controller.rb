# Relatório baixado de Anúncios (#1960): GET meta_ads_connection/report?formato=pdf|planilha&period= (Panel::Period, #2011). Quem vê o painel
# baixa (administrador ou `meta_ads_view`, policy Crm::MetaAdsConnection :show?); os números são os da tela no mesmo
# período, da conexão ou, sem ela, do WhatsApp (Crm::MetaAdsPanelSource). As listas trazem só as conversas que a pessoa
# já vê, e só para quem pode exportar o CRM (Crm::CardPolicy#export?, crm_export: dado pessoal em lote); sem isso o
# arquivo sai só com os números. Sem painel (nem conexão pronta nem Anúncios sem login), 404.
class Api::V1::Accounts::Crm::MetaAdsReportsController < Api::V1::Accounts::Crm::BaseController
  include ::Crm::MetaAdsPanelSource

  FORMATOS = {
    'pdf' => [::Crm::MetaAds::Relatorio::Pdf, 'application/pdf'],
    'planilha' => [::Crm::MetaAds::Relatorio::Planilha, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
  }.freeze

  before_action :ensure_allowed

  def show
    klass, content_type = FORMATOS[params[:formato]]
    return render_unprocessable('invalid_format') if klass.nil?
    return render json: { error: 'not_found' }, status: :not_found unless panel_ready?

    scope = panel_scope
    dados = ::Crm::MetaAds::Relatorio::Dados.new(panel_source, **scope, com_pessoas: Pundit.policy!(pundit_user, ::Crm::Card).export?)
    arquivo = klass.new(dados)
    send_data arquivo.gerar, filename: arquivo.nome, type: content_type, disposition: :attachment
  end

  private

  def ensure_allowed
    return if Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).show?

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def current_connection
    ::Crm::MetaAdsConnection.find_by(account_id: Current.account.id)
  end
end
