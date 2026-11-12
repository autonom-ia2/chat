# "Automações deste card" (#2499 F6.3): o que roda neste card agora e "Parar para este card" (Autonomia::Automacao::NoCard).
#
# Parecer de Funções: ver pede `automation_view` (DefinicaoPolicy#do_card?) e o card visível (CardPolicy#show?); parar
# pede `automation_manage` (DefinicaoPolicy#parar_no_card?) e poder mexer no card (CardPolicy#update?: no EE,
# crm_manage_cards e o funil do card). Tudo no escopo da conta.
#
# A tela tem flag própria (`automacao_no_crm`, decisão do Rodrigo em 12/11): sem ela, a lista e o parar dão 404. Com
# ela, a lista pede também o motor com os gatilhos de card (automacao_motor + automacao_gatilhos, Motor.gatilhos?).
# Parar não pede o motor, como o desligar (D7): com os gatilhos desligados, a execução que ainda estiver aberta fecha
# do mesmo jeito. Parar fecha também as filhas em outro registro (Autonomia::Automacao::NoCard).
class Api::V1::Accounts::Crm::Cards::AutomacoesController < Api::V1::Accounts::Crm::BaseController
  DEFINICAO = ::Autonomia::Automacao::Definicao
  FLAG = 'automacao_no_crm'.freeze

  before_action :exigir_tela
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

  def exigir_tela
    head :not_found unless Current.account.feature_enabled?(FLAG)
  end

  def exigir_motor
    head :not_found unless ::Autonomia::Automacao::Motor.gatilhos?(Current.account)
  end

  def carregar_card
    @card = Current.account.crm_cards.find_by(id: params[:card_id])
    head :not_found if @card.nil?
  end

  def no_card = ::Autonomia::Automacao::NoCard.new(card: @card, account_user: Current.account_user)
end
