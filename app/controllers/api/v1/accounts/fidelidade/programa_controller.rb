# O cartão fidelidade da conta (#3100): ler (o cartão ou null), criar ou mudar as regras (PUT, MontarPrograma) e pausar
# ou ligar de novo (PATCH { ligado }, PainelDoCartao). A regra de cada campo está em Fidelidade::Programa; o que muda
# ao criar, mudar, pausar e ligar, em Fidelidade::GravarPrograma.
class Api::V1::Accounts::Fidelidade::ProgramaController < Api::V1::Accounts::Fidelidade::BaseController
  before_action -> { conferir(:view?) }, only: :show
  before_action -> { conferir(:manage?) }, only: [:update, :ligar]

  def show
    render json: programa&.para_a_tela
  end

  def update
    gravado = gravar.gravar(params.require(:programa).permit(*::Fidelidade::GravarPrograma::CAMPOS))
    return render json: { errors: gravado.errors.to_hash }, status: :unprocessable_entity if gravado.errors.any?

    render json: gravado.para_a_tela
  end

  def ligar
    ligado = ActiveModel::Type::Boolean.new.cast(params.require(:ligado))
    gravado = gravar.ligar(ligado)
    return head :not_found unless gravado

    render json: gravado.para_a_tela
  end

  private

  def gravar = ::Fidelidade::GravarPrograma.new(Current.account, Current.user)
end
