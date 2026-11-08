# O que a gaveta "Metas do mês" alcança (#1991, F4 do #1871): os funis de Vender ativos que quem define enxerga no
# painel, e em cada um quem vende e enxerga o funil no Kanban, pela régua de papel do "Só eu" (Crm::Numeros::Papel:
# vendeu no mês, tem card aberto em funil de Vender ou, sem nada disso, enxerga funil de Vender). Quem só atende fica
# de fora, a não ser que já tenha meta no funil neste mês ou no anterior. A gaveta (Crm::Metas::Gaveta) e a gravação
# (Crm::Metas::Salvar) usam a mesma régua.
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
    pessoas.select do |pessoa|
      (vende?(pessoa.id) && enxergam[pessoa.id].include?(funil.id)) || com_meta.include?([funil.id, pessoa.id])
    end
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

  # Os funis (todos, não só os de Vender) que cada pessoa enxerga no Kanban, como no "Só eu".
  def enxergam
    @enxergam ||= membros.to_h do |membro|
      visiveis = Crm::Access::VisiblePipelines.new(user: membro.user, account: @account, account_user: membro)
                                              .apply(@account.crm_pipelines).pluck(:id)
      [membro.user_id, visiveis]
    end
  end

  def vende?(user_id)
    fechou = fechados_no_mes[user_id]
    abertos = abertos_por_dono[user_id].select { |pipeline_id| enxergam[user_id].include?(pipeline_id) }
    Crm::Numeros::Papel.de(
      vendeu: fechou.include?('won') || abertos.any? { |pipeline_id| venda?(pipeline_id) },
      atendeu: fechou.include?('resolved') || abertos.any? { |pipeline_id| !venda?(pipeline_id) }
    ) { enxergam[user_id].map { |pipeline_id| venda?(pipeline_id) }.uniq }.include?(:venda)
  end

  def venda?(pipeline_id)
    tipos.fetch(pipeline_id, false)
  end

  def tipos
    @tipos ||= @account.crm_pipelines.pluck(:id, :counts_as_sale).to_h
  end

  def fechados_no_mes
    @fechados_no_mes ||= Crm::Metas::Vendido.new(account: @account, range: @mes.range).status_por_pessoa
  end

  def abertos_por_dono
    @abertos_por_dono ||= begin
      abertos = Crm::Relacao.cards_do_funil(@account).where(status: Crm::Card.statuses[:open]).where.not(owner_id: nil)
      abertos.distinct.pluck(:owner_id, :pipeline_id).each_with_object(Hash.new { |hash, chave| hash[chave] = [] }) do |(dono, funil), mapa|
        mapa[dono] << funil
      end
    end
  end

  def com_meta
    @com_meta ||= Crm::PersonGoal.where(account_id: @account.id, pipeline_id: funis.map(&:id),
                                        month: [mes_do_banco, mes_do_banco.prev_month])
                                 .pluck(:pipeline_id, :user_id)
  end
end
