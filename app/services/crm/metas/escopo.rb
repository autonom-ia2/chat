# O que a gaveta "Metas do mês" alcança (#1991, F4 do #1871): os funis de Vender ativos que quem define enxerga no
# painel, e em cada um as pessoas da conta que trabalham nele (enxergam o funil no Kanban) ou já têm meta no mês.
# A gaveta (Crm::Metas::Gaveta) e a gravação (Crm::Metas::Salvar) usam a mesma régua.
class Crm::Metas::Escopo
  def initialize(account:, user:, account_user:, mes:)
    @account = account
    @user = user
    @account_user = account_user
    @mes = mes
  end

  def funis
    @funis ||= Crm::Access::VisiblePipelines.new(user: @user, account: @account, account_user: @account_user)
                                            .apply_to_reports(@account.crm_pipelines.active.where(counts_as_sale: true))
                                            .order(is_default: :desc, position: :asc, id: :asc).to_a
  end

  def pessoas_de(funil)
    pessoas.select { |pessoa| enxergam[pessoa.id].include?(funil.id) || com_meta.include?([funil.id, pessoa.id]) }
  end

  def mes_do_banco
    @mes.inicio.to_date
  end

  def self.moeda_de(funil)
    ((funil.metadata || {})['goals'] || {})['currency'].presence || 'BRL'
  end

  private

  def membros
    @membros ||= @account.account_users.where(integration: false).includes(:user).to_a
  end

  def pessoas
    @pessoas ||= membros.filter_map(&:user).sort_by { |pessoa| [pessoa.name.to_s.downcase, pessoa.id] }
  end

  def enxergam
    @enxergam ||= membros.to_h do |membro|
      visiveis = Crm::Access::VisiblePipelines.new(user: membro.user, account: @account, account_user: membro)
                                              .apply(@account.crm_pipelines.where(id: funis.map(&:id))).pluck(:id)
      [membro.user_id, visiveis]
    end
  end

  def com_meta
    @com_meta ||= Crm::PersonGoal.where(account_id: @account.id, pipeline_id: funis.map(&:id), month: mes_do_banco)
                                 .pluck(:pipeline_id, :user_id)
  end
end
