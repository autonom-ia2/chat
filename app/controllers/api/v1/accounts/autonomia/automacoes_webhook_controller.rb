# O segredo da assinatura do passo "webhook" de uma automação (G13, #2670): ver e trocar. É um segredo que a plataforma
# gera: o administrador ou a função com `token_manage` (regra de delegação, #1782; a chave cita o segredo de assinatura
# de webhook). Funções com `automation_manage` e `integration_manage` montam o passo, mas não leem o segredo.
#
# A resposta não fica em cache nem em log (o Rails não registra o corpo da resposta), e o segredo não é gravado em
# lugar nenhum: é derivado na hora (SegredoDoWebhook). A chave é `secret` de propósito: o Guia corta do que manda ao
# modelo toda chave da lista de segredos (Autonomia::Guide::Resumo::SEGREDOS), e o valor nunca vai para a IA.
class Api::V1::Accounts::Autonomia::AutomacoesWebhookController < Api::V1::Accounts::BaseController
  DEFINICAO = ::Autonomia::Automacao::Definicao

  wrap_parameters false

  before_action :exigir_flag
  before_action :exigir_chave_de_tokens
  before_action :carregar_automacao

  def segredo
    responder(::Autonomia::Automacao::SegredoDoWebhook.new(@automacao).valor)
  end

  def trocar_segredo
    responder(::Autonomia::Automacao::SegredoDoWebhook.new(@automacao).trocar!)
  end

  private

  def exigir_flag
    conta = Current.account
    ativo = conta.feature_enabled?(::Api::V1::Accounts::Autonomia::AutomacoesController::FLAG) &&
            ::Autonomia::Automacao::Motor.gatilhos_sem_crm?(conta)
    head :not_found unless ativo
  end

  def exigir_chave_de_tokens
    head :forbidden unless Current.account_user&.permission_granted?('token_manage')
  end

  def carregar_automacao
    @automacao = DEFINICAO.where(account: Current.account).find_by(id: params[:id])
    head :not_found if @automacao.nil?
  end

  def responder(segredo)
    response.headers['Cache-Control'] = 'no-store'
    render json: { secret: segredo }
  end
end
