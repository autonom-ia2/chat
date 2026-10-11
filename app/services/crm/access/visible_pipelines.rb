# Funis que a pessoa enxerga no CRM (#1148, PR D, decisão do Rodrigo em 11/10): o seletor do Kanban e o painel do CRM
# mostram só os funis dela; quem só atende Vendas não fica sabendo dos números de Sinistro.
#
# Sem acesso por funil (todo mundo hoje, e administrador sempre): todos os funis, como antes. Com restrição, a pessoa
# vê o funil quando:
# - ele está ligado a uma caixa em que ela é membro sem restrição;
# - ou está liberado numa caixa em que ela é membro com restrição (todos os funis daquela caixa, ou os escolhidos);
# - ou não está ligado a caixa nenhuma (funil de cards avulsos, que o acesso por funil não restringe, ver CardScope).
# Em "Só as suas" os funis da caixa aparecem no Kanban (ela trabalha os cards dela ali), mas não no painel: o relatório
# soma os cards dos outros.
class Crm::Access::VisiblePipelines
  def initialize(user:, account:, account_user: nil)
    @user = user
    @account = account
    @scope = Crm::Access::ConversationScope.new(user: user, account: account, account_user: account_user)
  end

  def restricted?
    @scope.restricted?
  end

  # Kanban, etapas e lista de funis.
  def apply(pipelines)
    restricted? ? pipelines.where(id: ids(include_only_own: true)) : pipelines
  end

  # Painel do CRM: relatórios e resumo da Meta.
  def apply_to_reports(pipelines)
    restricted? ? pipelines.where(id: report_ids) : pipelines
  end

  def report_ids
    @report_ids ||= ids(include_only_own: false)
  end

  private

  def ids(include_only_own:)
    (free_inbox_pipeline_ids + restricted_pipeline_ids(include_only_own) + unlinked_pipeline_ids).uniq
  end

  # Caixa sem inbox (apagada) não liga o funil a nada.
  def links
    @links ||= Crm::PipelineInbox.where(account_id: @account.id).where.not(inbox_id: nil).pluck(:inbox_id, :pipeline_id)
  end

  def member_inbox_ids
    @member_inbox_ids ||= @user.inboxes.where(account_id: @account.id).pluck(:id)
  end

  def free_inbox_pipeline_ids
    (member_inbox_ids - @scope.restricted_inbox_ids).flat_map { |inbox_id| inbox_pipeline_ids(inbox_id) }
  end

  # Linha de uma caixa da qual ela já saiu não libera nada.
  def restricted_pipeline_ids(include_only_own)
    (@scope.restricted_inbox_ids & member_inbox_ids).flat_map do |inbox_id|
      access = @scope.access_for(inbox_id)
      if access.only_own?
        include_only_own ? inbox_pipeline_ids(inbox_id) : []
      elsif access.all_pipelines?
        inbox_pipeline_ids(inbox_id)
      else
        access.agent_pipelines.map(&:pipeline_id)
      end
    end
  end

  def inbox_pipeline_ids(inbox_id)
    links.filter_map { |link_inbox_id, pipeline_id| pipeline_id if link_inbox_id == inbox_id }
  end

  def unlinked_pipeline_ids
    @account.crm_pipelines.where.not(id: links.map(&:last)).pluck(:id)
  end
end
