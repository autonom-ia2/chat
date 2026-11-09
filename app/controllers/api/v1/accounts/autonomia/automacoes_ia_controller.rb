# A IA das automações pela tela (#2500 C2): o "Testar este passo" e os custos (a soma de cada automação, para a lista,
# e a média de cada passo, para o cartão). Fora do AutomacoesController, com as mesmas travas: a flag do editor e a
# policy da Definicao.
#
# - Testar chama a IA e paga: pede `automation_manage` e a flag da F7 (`automacao_ia`). O rascunho passa pela mesma
#   conferência do salvar (esquema + Receita) antes de qualquer chamada.
# - As agentes de IA do passo "Passar para a agente de IA" (G15) pedem `automation_manage`, como montar a automação.
# - Valor em dinheiro (os custos e o custo do teste) só para administrador ou `financial_view`, como o
#   Crm::AiUsageController#com_valores? (#1969, #2557). Sem ela, os custos voltam vazios e a tela não mostra a linha.
class Api::V1::Accounts::Autonomia::AutomacoesIaController < Api::V1::Accounts::BaseController
  DEFINICAO = ::Autonomia::Automacao::Definicao
  CUSTOS = ::Autonomia::Automacao::CustosDaIa
  FLAG = ::Api::V1::Accounts::Autonomia::AutomacoesController::FLAG

  wrap_parameters false

  before_action :exigir_flag
  before_action :autorizar

  def testar_passo
    return head :not_found unless ::Autonomia::Automacao::Motor.ia?(Current.account)

    problemas = problemas_do_rascunho
    return recusar('receita_invalida', problemas) if problemas.any?

    render json: teste.resultado(com_valores: com_valores?)
  rescue ::Autonomia::Automacao::TestarPasso::Recusa => e
    recusar(e.chave)
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # `com_valores` diz à tela se ela mostra a linha do custo: vazio sem permissão não é "ainda não custou".
  def custos
    render json: { com_valores: com_valores?, custos: com_valores? ? CUSTOS.por_automacao(escopo.ids) : {} }
  end

  # G15: as agentes de IA que o passo "Passar para a agente de IA" oferece. Só id e nome: nada da configuração delas.
  def agentes_de_ia
    render json: { agentes: ::Autonomia::Automacao::PassoDeIaAssumir.opcoes(Current.account) }
  end

  def custos_da_automacao
    automacao = escopo.find_by(id: params[:id])
    return head :not_found if automacao.nil?

    render json: { com_valores: com_valores?, custos: com_valores? ? CUSTOS.por_passo(automacao.id) : {} }
  end

  private

  def exigir_flag
    head :not_found unless Current.account.feature_enabled?(FLAG)
  end

  def autorizar
    authorize(DEFINICAO, "#{action_name}?")
  end

  def escopo
    DEFINICAO.where(account: Current.account)
  end

  def com_valores?
    Current.account_user&.permission_granted?('financial_view') || false
  end

  # A receita é livre de propósito: o esquema e a Receita conferem tudo, com erro em frase.
  def receita
    valor = params[:receita]
    valor.respond_to?(:to_unsafe_h) ? valor.to_unsafe_h : valor
  end

  def problemas_do_rascunho
    return [I18n.t('autonomia.automacao.ensaio.sem_receita')] unless receita.is_a?(Hash) && ::Autonomia::Automacao::Receita.esquema_valido?(receita)

    ::Autonomia::Automacao::Receita.new(receita, conta: Current.account, account_user: Current.account_user).problemas
  end

  # `automacao_id`: a automação já salva que está sendo editada; quem a ligou também precisa poder ver o valor do card
  # (#2780). Sem ela (a nova), só quem testa.
  def teste
    ::Autonomia::Automacao::TestarPasso.new(receita: receita, passo_id: params[:passo_id], conta: Current.account,
                                            account_user: Current.account_user, conversa_id: params[:conversa_id],
                                            ligada_por: escopo.find_by(id: params[:automacao_id])&.ligada_por)
  end

  def recusar(chave, problemas = [])
    render json: { error: I18n.t("autonomia.automacao.testar.#{chave}"), problemas: problemas }, status: :unprocessable_entity
  end
end
