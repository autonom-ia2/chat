# #3100 — o cartão fidelidade da pessoa, na ficha: ler (o cartão da conta, o saldo, o que vence, os últimos movimentos
# e os cupons dela), o histórico inteiro por página, dar o prêmio e dar ou tirar carimbos à mão.
#
# Ler segue a ficha (quem vê a lista de Relacionamentos). Dar o prêmio é de quem pode mexer no contato, inclusive o
# atendente (decisão D1 do Rodrigo, 23/11), e aceita a chave de idempotência (Idempotency-Key): o mesmo toque repetido
# devolve a mesma resposta e não tira a meta duas vezes. Dar ou tirar à mão pede `fidelidade_manage`.
# O valor da compra no histórico só vai para quem vê valor de venda (Crm::ValorDeVenda).
class Api::V1::Accounts::Relacionamentos::FidelidadeController < Api::V1::Accounts::Relacionamentos::BaseController
  include ::Crm::IdempotentRequests

  before_action :achar_pessoa
  before_action :sem_parametros, only: :show
  before_action :com_cartao, only: [:premios, :ajustes]

  rescue_from ::Fidelidade::Carteira::SaldoInsuficiente do
    render json: { error: 'saldo_insuficiente' }, status: :unprocessable_entity
  end

  # O motivo do ajuste maior que o campo (Fidelidade::Movimento::MOTIVO_MAXIMO).
  rescue_from ActiveRecord::RecordInvalid do |erro|
    render json: { errors: erro.record.errors.to_hash }, status: :unprocessable_entity
  end

  def show
    render json: da_pessoa.call
  end

  def movimentos
    render json: da_pessoa.movimentos_da_pagina(pagina)
  end

  def premios
    authorize @pessoa, :update?
    with_idempotency do
      movimento = ::Fidelidade::DarPremio.new(@programa, @pessoa, Current.user).call
      render json: resposta(movimento), status: :created
    end
  end

  def ajustes
    authorize(::Fidelidade::Programa, :manage?, policy_class: ::Fidelidade::ProgramaPolicy)
    quantos = Integer(params.require(:quantos).to_s, 10, exception: false)
    return render json: { error: 'quantos_invalido' }, status: :unprocessable_entity if quantos.nil? || quantos.zero?

    movimento = ::Fidelidade::Ajustar.new(@programa, @pessoa, Current.user).call(quantos, params[:motivo].to_s.strip)
    render json: resposta(movimento), status: :created
  end

  private

  def idempotency_namespace = 'fidelidade_premio'

  def achar_pessoa
    @pessoa = Current.account.contacts.find(params[:pessoa_id])
  end

  def com_cartao
    @programa = ::Fidelidade::Programa.da_conta(Current.account)
    head :not_found unless @programa
  end

  def da_pessoa
    ::Fidelidade::DaPessoa.new(Current.account, @pessoa, com_valores: ::Crm::ValorDeVenda.ve?(Current.account_user))
  end

  def pagina
    numero = Integer(params[:pagina].presence || '1', 10, exception: false)
    recusar("pagina inválida: #{params[:pagina]}") unless numero&.positive?
    numero
  end

  # O movimento gravado e o cartão da pessoa como ficou, para a ficha se refazer sem outra leitura.
  def resposta(movimento)
    { movimento: movimento.para_a_tela(com_valores: false), fidelidade: da_pessoa.call }
  end
end
