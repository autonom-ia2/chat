# "Automações desta etapa" (#2499 F6.5): as automações do motor novo com gatilho nesta etapa (Autonomia::Automacao::DaEtapa).
# Ligar e desligar cada uma é o da própria automação (AutomacoesController#ligar/#desligar: assumir e religar); as regras
# antigas da etapa vêm do StageAutomationsController.
#
# Parecer de Funções: ver pede `automation_view` e a chave de funis (crm_manage_pipelines ou crm_admin,
# DefinicaoPolicy#da_etapa?), como a tela da etapa no "Editar funil". A etapa é da conta. Só com o motor e os gatilhos
# de card (Motor.gatilhos?) e com a flag da tela (`automacao_no_crm`, a mesma das automações do card): sem ela, 404.
class Api::V1::Accounts::Crm::StageAutomacoesController < Api::V1::Accounts::Crm::BaseController
  DEFINICAO = ::Autonomia::Automacao::Definicao
  FLAG = 'automacao_no_crm'.freeze

  before_action :exigir_tela
  before_action :exigir_motor

  def index
    authorize DEFINICAO, :da_etapa?
    etapa = ::Crm::PipelineStage.find_by(account_id: Current.account.id, id: params[:stage_id])
    return head :not_found if etapa.nil?

    render json: { automacoes: ::Autonomia::Automacao::DaEtapa.de(etapa).map { |automacao| para_tela(automacao) } }
  end

  private

  def exigir_tela
    head :not_found unless Current.account.feature_enabled?(FLAG)
  end

  def exigir_motor
    head :not_found unless ::Autonomia::Automacao::Motor.gatilhos?(Current.account)
  end

  def para_tela(automacao)
    versao = automacao.versao_ativa
    { id: automacao.id, nome: automacao.nome, ativa: automacao.ativa,
      versao: { id: versao.id, receita: versao.receita_para_tela(Current.account_user) } }
  end
end
