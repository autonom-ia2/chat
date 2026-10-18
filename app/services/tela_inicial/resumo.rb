# Números da tela inicial da caixa de conversas (#1801, opção 2 "Resumo do dia"). Só leitura, contados no servidor.
#
# Da pessoa, sobre as conversas abertas que ela pode ver (Conversations::PermissionFilterService, que o EE estende com
# as funções personalizadas):
# - esperam: "Não atendidas" do Chatwoot (sem primeira resposta ou com o cliente esperando), no nome dela.
# - sem_responsavel: a aba "Não atribuídas" (sem pessoa no nome, inclusive as que o robô passou e esperam alguém).
# - fora_do_prazo: no nome dela, com o prazo de resposta perdido. nil quando a conta não usa prazos.
# - proxima: a dela que espera há mais tempo.
# Da equipe, os totais da conta: só para quem tem report_manage (a chave dos relatórios; no OSS, o administrador).
class TelaInicial::Resumo
  NAO_ATENDIDA_SQL = '(conversations.first_reply_created_at IS NULL OR conversations.waiting_since IS NOT NULL)'.freeze
  SEM_RESPONSAVEL_SQL = "COUNT(*) FILTER (WHERE #{Conversation::AWAITING_PERSON_SQL})".freeze

  def initialize(account:, user:, account_user:)
    @account = account
    @user = user
    @account_user = account_user
  end

  def perform
    esperam, sem_responsavel = visiveis.unscope(:order).pick(Arel.sql(minhas_sql(NAO_ATENDIDA_SQL)), Arel.sql(SEM_RESPONSAVEL_SQL))
    resumo = { esperam: esperam, sem_responsavel: sem_responsavel, fora_do_prazo: minhas_fora_do_prazo, proxima: proxima }
    return resumo unless ve_a_equipe?

    resumo.merge(equipe: equipe)
  end

  private

  attr_reader :account, :user, :account_user

  def visiveis
    @visiveis ||= Conversations::PermissionFilterService.new(account.conversations, user, account).perform.open
  end

  def minhas_sql(condicao)
    Conversation.sanitize_sql_array(["COUNT(*) FILTER (WHERE conversations.assignee_id = ? AND #{condicao})", user.id])
  end

  # O status do prazo é o que o servidor grava (job do SLA).
  def minhas_fora_do_prazo
    return unless usa_prazo?

    visiveis.where(assignee_id: user.id).joins(:applied_sla).merge(AppliedSla.missed).count
  end

  def equipe
    da_conta = account.conversations.open
    esperam, sem_responsavel = da_conta.pick(Arel.sql("COUNT(*) FILTER (WHERE #{NAO_ATENDIDA_SQL})"), Arel.sql(SEM_RESPONSAVEL_SQL))
    fora = da_conta.joins(:applied_sla).merge(AppliedSla.missed).count if usa_prazo?
    { esperam: esperam, sem_responsavel: sem_responsavel, fora_do_prazo: fora }
  end

  def usa_prazo?
    return @usa_prazo if defined?(@usa_prazo)

    @usa_prazo = ChatwootApp.enterprise? && account.feature_enabled?('sla') && SlaPolicy.exists?(account_id: account.id)
  end

  def proxima
    conversa = visiveis.where(assignee_id: user.id).where(NAO_ATENDIDA_SQL)
                       .sort_on_waiting_since(:asc).includes(:contact).first
    return if conversa.blank?

    {
      id: conversa.id,
      display_id: conversa.display_id,
      nome_do_contato: conversa.contact&.name,
      # Desde quando espera: a mensagem sem resposta; sem ela (ainda sem primeira resposta), o começo da conversa.
      waiting_since: (conversa.waiting_since || conversa.created_at).to_i
    }
  end

  # Totais da conta: a mesma chave dos relatórios. conversation_manage não basta: cobre só as caixas da pessoa.
  def ve_a_equipe?
    account_user.present? && account_user.permission_granted?('report_manage')
  end
end
