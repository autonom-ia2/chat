# #3099: as duas versões da mensagem na Automação livre, pelo Histórico da automação.
#
#   GET  …/autonomia/automacoes/:id/duas_versoes                    { passos: [bloco de cada passo] }
#   POST …/autonomia/automacoes/:id/duas_versoes/vencedora    { passo: id do passo, versao: 1 | 2 } → o bloco do passo
#
# O bloco é o de Autonomia::Automacao::DuasVersoes::Teste#payload. Ver pede automation_view; escolher a versão que fica
# pede automation_manage (DefinicaoPolicy), como mudar a automação. Escolher é uma vez só: a mesma versão de novo
# responde 200; outra versão depois de escolhida responde 422. Passo que não testa duas versões na versão ativa: 404. O
# id do passo vai no corpo: o da receita é texto livre (o Guia também monta) e pode ter ponto ou barra.
# Com as mesmas travas do editor: a flag `automacao_editor` e a automação da conta.
class Api::V1::Accounts::Autonomia::AutomacoesDuasVersoesController < Api::V1::Accounts::BaseController
  DEFINICAO = ::Autonomia::Automacao::Definicao
  DUAS_VERSOES = ::Autonomia::Automacao::DuasVersoes

  wrap_parameters false

  before_action :exigir_flag
  before_action :autorizar
  before_action :carregar_automacao

  def duas_versoes
    render json: { passos: DUAS_VERSOES.resultado(@automacao, user: Current.user, account_user: Current.account_user) }
  end

  def escolher_versao
    passo = DUAS_VERSOES.passo_ativo(@automacao, params[:passo].to_s)
    return head :not_found if passo.nil?
    return recusar('versao_invalida') unless versao

    teste = DUAS_VERSOES::Teste.new(DUAS_VERSOES.teste_de(@automacao, passo['id']), passo)
    escolheu = teste.escolher!(versao, por: 'voce', user: Current.user)
    return recusar('versao_ja_escolhida') unless escolheu || teste.linha.vencedora == versao

    render json: teste.payload(user: Current.user, account_user: Current.account_user)
  end

  private

  def exigir_flag
    head :not_found unless Current.account.feature_enabled?(::Api::V1::Accounts::Autonomia::AutomacoesController::FLAG)
  end

  def autorizar
    authorize(DEFINICAO, "#{action_name}?")
  end

  def carregar_automacao
    @automacao = DEFINICAO.where(account: Current.account).find_by(id: params[:id])
    head :not_found if @automacao.nil?
  end

  def versao
    numero = params[:versao].to_s.to_i
    numero if DUAS_VERSOES::VERSOES.include?(numero)
  end

  def recusar(chave)
    render json: { error: I18n.t("autonomia.automacao.duas_versoes.#{chave}") }, status: :unprocessable_entity
  end
end
