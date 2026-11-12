# "Automações deste card" (#2499 F6.3): o que roda neste card agora e "Parar para este card" (Autonomia::Automacao::NoCard).
#
# Parecer de Funções: ver pede `automation_view` (DefinicaoPolicy#do_card?) e o card visível (CardPolicy#show?); parar
# pede `automation_manage` (DefinicaoPolicy#parar_no_card?) e poder mexer no card (CardPolicy#update?: no EE,
# crm_manage_cards e o funil do card). Tudo no escopo da conta.
#
# A lista pede o motor com os gatilhos de card (automacao_motor + automacao_gatilhos, Motor.gatilhos?). Parar sempre
# funciona, como o desligar (D7): com a flag desligada, a execução que ainda estiver aberta fecha do mesmo jeito.
class Api::V1::Accounts::Crm::Cards::AutomacoesController < Api::V1::Accounts::Crm::BaseController
  DEFINICAO = ::Autonomia::Automacao::Definicao

  before_action :exigir_motor, except: :parar
  before_action :carregar_card

  def index
    authorize DEFINICAO, :do_card?
    authorize @card, :show?
    render json: { automacoes: no_card.lista }
  end

  def parar
    authorize DEFINICAO, :parar_no_card?
    authorize @card, :update?
    automacao = DEFINICAO.find_by(account_id: Current.account.id, id: params[:id])
    return head :not_found if automacao.nil?

    render json: { paradas: no_card.parar!(automacao) }
  end

  private

  def exigir_motor
    head :not_found unless ::Autonomia::Automacao::Motor.gatilhos?(Current.account)
  end

  def carregar_card
    @card = Current.account.crm_cards.find_by(id: params[:card_id])
    head :not_found if @card.nil?
  end

  def no_card = ::Autonomia::Automacao::NoCard.new(card: @card, account_user: Current.account_user)
end
