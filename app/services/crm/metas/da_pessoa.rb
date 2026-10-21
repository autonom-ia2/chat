# A meta do mês de uma pessoa no topo de "Só eu" (#1991, F4 do #1871): a soma das metas dela nos funis de Vender, na
# moeda que o topo mostra, só de funis ativos (a gaveta não alcança o arquivado). Sem meta: nil (o topo diz "Seu mês
# até agora"). Só com a flag `crm_metas`.
class Crm::Metas::DaPessoa
  def initialize(account:, user:, mes:, moeda:)
    @account = account
    @user = user
    @mes = mes
    @moeda = moeda
  end

  def reais
    return unless Crm::Config.metas_enabled?(@account)

    cents = Crm::PersonGoal.joins(:pipeline)
                           .where(account_id: @account.id, user_id: @user.id, month: @mes.inicio.to_date, currency: @moeda,
                                  crm_pipelines: { counts_as_sale: true, status: Crm::Pipeline.statuses[:active] })
                           .sum(:target_cents)
    cents.positive? ? (cents / 100.0).round(2) : nil
  end
end
