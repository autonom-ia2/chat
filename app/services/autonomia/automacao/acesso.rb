# Quem ligou a automação, conferido a cada rodada (D1, D2, D5, F3.7 e F3.9). O motor age como essa pessoa, com o token
# dela, e nunca troca para outra: sem ela, sem a conta ou sem a permissão de gerenciar automações, a automação pausa.
#
# A caixa (D5) vale pelo próprio Pundit: `alcanca?` pergunta à política da conversa o mesmo que o endpoint perguntaria.
# Passo que sai da plataforma (webhook de saída, F8) vai pedir também integration_manage aqui.
class Autonomia::Automacao::Acesso
  PERMISSAO = 'automation_manage'.freeze

  attr_reader :usuario, :account_user

  # `chave_gatilho`: o gatilho da execução que está rodando (ou começando). Sem ele (ao ligar), vale o da versão ativa.
  # A execução em andamento segue a versão dela: salvar uma versão com outro gatilho não tira a checagem do funil.
  def initialize(definicao, chave_gatilho: nil)
    @definicao = definicao
    @chave_gatilho = chave_gatilho
    @account = definicao.account
    @usuario = definicao.ligada_por
    @account_user = @usuario && @account.account_users.find_by(user_id: @usuario.id)
  end

  # nil quando pode agir; senão a chave do motivo (autonomia.automacao.motivos.*).
  def motivo
    return 'sem_quem_ligou' unless @usuario
    return 'quem_ligou_saiu_da_conta' unless @account_user

    return 'quem_ligou_sem_permissao' unless @account_user.permission_granted?(PERMISSAO)

    'sem_permissao_funil' if gatilho_de_card? && !mexe_no_funil?
  end

  # O alvo é uma conversa, um card ou um contato (#2499). No card, valem o próprio card e a conversa principal dele, em
  # que os passos agem: a pergunta vai a cada política, e quem não vê um dos dois pausa a automação em vez de quebrar a
  # rodada. O contato pergunta à política do contato se pode mudá-lo (update?): o motor age, não só lê.
  def alcanca?(alvo)
    contexto = { user: @usuario, account: @account, account_user: @account_user }
    return ContactPolicy.new(contexto, alvo).update? if alvo.is_a?(::Contact)
    return ConversationPolicy.new(contexto, alvo).show? unless alvo.is_a?(::Crm::Card)

    conversa = alvo.primary_conversation
    ::Crm::CardPolicy.new(contexto, alvo).show? && (conversa.nil? || ConversationPolicy.new(contexto, conversa).show?)
  end

  # Gatilho de card (#2499, F6): quem ligou precisa poder mexer no funil, a mesma pergunta das automações de etapa
  # (Crm::StageAutomationPolicy#create?): no EE, crm_permission?('crm_manage_pipelines'), que conta o crm_admin e nega o
  # agente comum, junto com automation_manage; no OSS, só o administrador.
  def mexe_no_funil?
    contexto = { user: @usuario, account: @account, account_user: @account_user }
    ::Crm::StageAutomationPolicy.new(contexto, ::Crm::StageAutomation.new(account: @account)).create?
  end

  def gatilho_de_card?
    ::Autonomia::Automacao::Gatilhos.do_card?(@chave_gatilho || @definicao.versao_ativa&.receita&.dig('gatilho', 'tipo'))
  end

  # A mesma pergunta para outra pessoa da conta (quem o passo "avisar" menciona, F4). Quem confere várias pessoas passa
  # o vínculo já carregado.
  def self.alcanca?(usuario, conversa, account_user: conversa.account.account_users.find_by(user_id: usuario.id))
    account_user.present? &&
      ConversationPolicy.new({ user: usuario, account: conversa.account, account_user: account_user }, conversa).show?
  end
end
