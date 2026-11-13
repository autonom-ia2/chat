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

    'sem_permissao_funil' if !mexe_no_funil? && (gatilho_de_card? || le_o_card?)
  end

  # O motivo para não agir agora neste alvo, ou nil: quem ligou (`motivo`), a chave de funis na filha do "em outro
  # registro" (G18) que roda num card (ela pode vir de um gatilho de conversa; no gatilho de card, `motivo` já pediu a
  # mesma chave) e o alcance. A cada ação, no Executor.
  def motivo_no(alvo, execucao)
    return motivo if motivo
    return 'sem_chave_de_funis' if filha_no_card?(alvo, execucao) && !::Autonomia::Automacao::RegraDoFunil.chave?(@account_user)

    'quem_ligou_sem_acesso' unless alcanca?(alvo, execucao)
  end

  # A filha do "para cada" (#2932) nos cards de uma etapa também.
  def filha_no_card?(alvo, execucao) = alvo.is_a?(::Crm::Card) && ::Autonomia::Automacao::RepetirLista.filha?(execucao)

  # O alvo é uma conversa, um card ou um contato (#2499). No card, valem o próprio card e a conversa em que os passos
  # agem (a principal dele, ou a da mãe na filha do "em outro registro", G18: Contexto#conversa, a mesma que os passos
  # usam): a pergunta vai a cada política, e quem não vê um dos dois pausa a automação em vez de quebrar a rodada. O
  # contato pergunta à política do contato se pode mudá-lo (update?): o motor age, não só lê. A conta
  # (conta.recorrente, G7) é a da automação: quem ligou já passou pelo `motivo`.
  def alcanca?(alvo, execucao = nil)
    return alvo.id == @account.id if alvo.is_a?(::Account)
    return ContactPolicy.new(contexto, alvo).update? if alvo.is_a?(::Contact)
    return ConversationPolicy.new(contexto, alvo).show? unless alvo.is_a?(::Crm::Card)

    conversa = ::Autonomia::Automacao::Contexto.de(alvo, execucao: execucao).conversa
    ::Crm::CardPolicy.new(contexto, alvo).show? && (conversa.nil? || ConversationPolicy.new(contexto, conversa).show?)
  end

  # Gatilho de card (#2499, F6): quem ligou precisa poder mexer no funil, a mesma pergunta das automações de etapa
  # (Crm::StageAutomationPolicy#create?): no EE, crm_permission?('crm_manage_pipelines'), que conta o crm_admin e nega o
  # agente comum, junto com automation_manage; no OSS, só o administrador.
  def mexe_no_funil?
    ::Crm::StageAutomationPolicy.new(contexto, ::Crm::StageAutomation.new(account: @account)).create?
  end

  # O contexto do Pundit de quem ligou: o mesmo que o endpoint montaria para essa pessoa.
  def contexto = { user: @usuario, account: @account, account_user: @account_user }

  def gatilho_de_card?
    ::Autonomia::Automacao::Gatilhos.do_card?(@chave_gatilho || @definicao.versao_ativa&.receita&.dig('gatilho', 'tipo'))
  end

  # A automação de conversa que lê o card (#2716) pede a mesma pergunta do gatilho de card; a âncora e o ramo do "em
  # outro registro", com `origem.card.*`, também (CardDaConversa.le?, decisão 19). Sem ela, pausa com o motivo,
  # em vez de ler o card vazio e deixar o "Só se" falso em silêncio. Vale a versão ativa e a das execuções em andamento:
  # cada uma segue a versão em que começou.
  def le_o_card?
    ids = [@definicao.versao_ativa_id, *@definicao.execucoes.abertas.distinct.pluck(:versao_id)].compact.uniq
    ::Autonomia::Automacao::Versao.where(id: ids).any? { |versao| ::Autonomia::Automacao::CardDaConversa.le?(versao.receita) }
  end

  # As mesmas perguntas do "Nova conversa" do painel: administrador ou membro da caixa (o controller confere), e a
  # ConversationPolicy deixa começar conversa (o EE recusa a função que só lê). O passo "email" e a conversa nova de
  # quem não tem conversa (ConversaNova, #2680) perguntam aqui, ao salvar e a cada abertura.
  def self.comeca_conversa?(account_user, caixa)
    usuario = account_user.user
    return false unless account_user.administrator? || usuario.inboxes.exists?(id: caixa.id)

    ConversationPolicy.new({ user: usuario, account: account_user.account, account_user: account_user }, Conversation).create?
  end

  # A mesma pergunta pela pessoa (quem ligou a automação, ou quem vai ligar no ensaio, #2604): quem saiu da conta não
  # começa.
  def self.pessoa_comeca_conversa?(usuario, caixa)
    account_user = usuario && caixa.account.account_users.find_by(user_id: usuario.id)
    account_user.present? && comeca_conversa?(account_user, caixa)
  end

  # A mesma pergunta para outra pessoa da conta (quem o passo "avisar" menciona, F4). Quem confere várias pessoas passa
  # o vínculo já carregado.
  def self.alcanca?(usuario, conversa, account_user: conversa.account.account_users.find_by(user_id: usuario.id))
    account_user.present? &&
      ConversationPolicy.new({ user: usuario, account: conversa.account, account_user: account_user }, conversa).show?
  end
end
