# Quem ligou a automação, conferido a cada rodada (D1, D2, D5, F3.7 e F3.9). O motor age como essa pessoa, com o token
# dela, e nunca troca para outra: sem ela, sem a conta ou sem a permissão de gerenciar automações, a automação pausa.
#
# A caixa (D5) vale pelo próprio Pundit: `alcanca?` pergunta à política da conversa o mesmo que o endpoint perguntaria.
# Passo que sai da plataforma (webhook de saída, F8) vai pedir também integration_manage aqui.
class Autonomia::Automacao::Acesso
  PERMISSAO = 'automation_manage'.freeze

  attr_reader :usuario, :account_user

  def initialize(definicao)
    @account = definicao.account
    @usuario = definicao.ligada_por
    @account_user = @usuario && @account.account_users.find_by(user_id: @usuario.id)
  end

  # nil quando pode agir; senão a chave do motivo (autonomia.automacao.motivos.*).
  def motivo
    return 'sem_quem_ligou' unless @usuario
    return 'quem_ligou_saiu_da_conta' unless @account_user

    'quem_ligou_sem_permissao' unless @account_user.permission_granted?(PERMISSAO)
  end

  def alcanca?(conversa)
    ConversationPolicy.new({ user: @usuario, account: @account, account_user: @account_user }, conversa).show?
  end
end
