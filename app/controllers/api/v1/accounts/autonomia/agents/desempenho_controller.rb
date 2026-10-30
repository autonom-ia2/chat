# Painel de desempenho do agente (#2251, épico #2226): o painel de um período e a exportação em PDF e planilha.
#
#   GET /api/v1/accounts/:account_id/autonomia/agents/:agent_id/desempenho?periodo=7|30|90|tudo[&origem=webhook]
#   GET /api/v1/accounts/:account_id/autonomia/agents/:agent_id/desempenho/exportar?formato=pdf|xlsx&periodo=...
#
# `origem=webhook` é o robô de outro sistema (AgentBot da conta); sem ela, o agente nosso. Os ids podem coincidir,
# como na página do agente (#1648).
#
# Controller próprio, fora do Autonomia::BaseController (que exige autonomia_view): ver o painel é a chave
# `desempenho_view`, independente da de agentes (ESPEC 6.1). No OSS, só administrador. Atrás da flag da conta
# `agentes_painel_desempenho` e do módulo de Agentes; desligado, 404.
#
# Os números são das caixas que a pessoa vê (ESPEC 6.2; admin vê a conta inteira), e o dinheiro (ticket e ganho em
# R$) segue `sales_value_view` (Autonomia::Desempenho::Painel e Visibilidade). Sem leitura guardada para o agente, o
# painel vem vazio, com a situação `leitura_desligada` (ou, com a leitura automática ligada para ele, a da rodada:
# Autonomia::Desempenho::Painel.situacao_sem_procuras).
class Api::V1::Accounts::Autonomia::Agents::DesempenhoController < Api::V1::Accounts::BaseController
  FLAG = 'agentes_painel_desempenho'.freeze
  FORMATOS = {
    'pdf' => ['Autonomia::Desempenho::Exportacao::Pdf', 'application/pdf'],
    'xlsx' => ['Autonomia::Desempenho::Exportacao::Planilha', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
  }.freeze

  before_action :ensure_feature_enabled
  before_action -> { check_module_permission!('desempenho') }
  # Baixar o arquivo é exportar dados da base (ESPEC 6.3): pede também contact_export.
  before_action -> { check_permission_granted!('contact_export') }, only: :exportar
  before_action :fetch_sujeito

  def show
    render json: painel || vazio
  end

  def exportar
    classe, tipo = FORMATOS[params[:formato].to_s]
    return render json: { error: I18n.t('autonomia.desempenho2.api.formato_invalido') }, status: :unprocessable_entity if classe.nil?

    atual = painel
    return render json: { error: I18n.t('autonomia.desempenho2.api.sem_leitura') }, status: :not_found if atual.nil? || atual['vazio']

    send_data classe.constantize.new(atual).gerar, type: tipo, disposition: 'attachment',
                                                   filename: "desempenho-#{atual.dig('meta', 'periodo', 'chave')}.#{params[:formato]}"
  end

  private

  def ensure_feature_enabled
    head :not_found unless ::Autonomia::Agents::Config.enabled?(Current.account) && Current.account.feature_enabled?(FLAG)
  end

  # Sempre presos à conta corrente; robô de sistema (sem conta) e agente de sistema (o Guia) ficam de fora.
  def fetch_sujeito
    if params[:origem] == 'webhook'
      @sujeito = ['robo', AgentBot.where(account_id: Current.account.id).find(params[:agent_id]).id]
    else
      agente = ::Autonomia::Agents::Agent.kept.where(account: Current.account).where("config->>'system_key' IS NULL").find(params[:agent_id])
      @sujeito = ['agente', agente.id]
    end
  end

  def painel
    @painel ||= ::Autonomia::Desempenho::Painel.new(
      account: Current.account, sujeito_type: @sujeito.first, sujeito_id: @sujeito.last,
      visiveis: ::Autonomia::ContaDaIa.visiveis(user: Current.user, account: Current.account),
      ve_valores: ::Crm::ValorDeVenda.ve?(Current.account_user)
    ).call(params[:periodo])
  end

  def vazio
    pedido = params[:periodo].to_s
    chave = ::Autonomia::Desempenho::Painel::PERIODOS.include?(pedido) ? pedido : ::Autonomia::Desempenho::Painel::PADRAO
    { 'versao' => 2, 'vazio' => true,
      'meta' => { 'fonte' => ::Autonomia::Desempenho::Painel::FONTE, 'periodo' => { 'chave' => chave },
                  'situacao' => ::Autonomia::Desempenho::Painel.situacao_sem_procuras(Current.account, *@sujeito),
                  'dados_ate' => nil, 'base' => nil, 'agente' => nil } }
  end
end
