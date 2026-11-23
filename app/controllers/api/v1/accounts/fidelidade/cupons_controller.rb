# Os cupons da conta (#3100, aba Cupons): o relatório (GET), criar (POST, MontarCupom), pausar ou ligar de novo
# (PATCH { ligado }) e conferir um código que o cliente mostrou (POST conferir { codigo }).
#
# Ver o relatório e conferir pedem `fidelidade_view`; criar, pausar e ligar, `fidelidade_manage`
# (Fidelidade::ProgramaPolicy). O valor vendido só vai para quem vê valor de venda (Fidelidade::RelatorioDosCupons).
# O conferir tem limite de tentativas por pessoa (rack_attack.rb) e só diz o nome do cliente a quem pode ver o contato.
# Marcar o código como usado mora em CupomCodigosController (quem pode mexer no contato, D1).
class Api::V1::Accounts::Fidelidade::CuponsController < Api::V1::Accounts::Fidelidade::BaseController
  before_action -> { conferir(:view?) }, only: [:index, :conferir]
  before_action -> { conferir(:manage?) }, only: [:create, :update]

  def index
    render json: relatorio.call
  end

  def create
    cupom = gravar.criar(params.require(:cupom).permit(*::Fidelidade::GravarCupom::CAMPOS))
    return render json: { errors: cupom.errors.to_hash }, status: :unprocessable_entity if cupom.errors.any?

    render json: relatorio.um(cupom), status: :created
  end

  def update
    cupom = ::Fidelidade::Cupom.da_conta(Current.account).find(params[:id])
    ligado = ActiveModel::Type::Boolean.new.cast(params.require(:ligado))
    render json: relatorio.um(gravar.ligar(cupom, ligado))
  end

  def conferir
    resposta = ::Fidelidade::ConferirCupom.new(Current.account, ve_contato: ->(contato) { policy(contato).show? })
                                          .call(params.require(:codigo))
    render json: resposta
  end

  private

  def gravar = ::Fidelidade::GravarCupom.new(Current.account, Current.user)

  def relatorio = ::Fidelidade::RelatorioDosCupons.new(Current.account, user: Current.user, account_user: Current.account_user)
end
