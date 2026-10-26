# O gasto com anúncios do mês em Números › "De onde vieram os clientes" (#2001, F6 do #1871): o que a coleta diária
# da Meta guardou (Crm::MetaAdInsightDaily, a mesma fonte do painel de Anúncios) para a conta de anúncios conectada,
# nos dias do mês da tela (no fuso da conta). A Meta grava cada dia no fuso da conta de anúncios; quando os dois fusos
# diferem, a virada do mês pode cair num dia vizinho, como no painel de Anúncios no período "Este mês".
#
# Só existe com a conexão ativa e uma conta de anúncios escolhida; sem isso, ou com gasto zero, `existe?` é falso e a
# tela não mostra nada de gasto (regra do Rodrigo, 21/10: nem zero, nem traço).
# "Toques" são os cliques no link do anúncio (link_clicks): o que a Meta conta de quem tocou para abrir a conversa.
class Crm::Numeros::Origens::Gasto
  def initialize(account:, mes:)
    @account = account
    @mes = mes
  end

  def existe?
    total.positive?
  end

  # { ad_id => gasto em reais }
  def por_anuncio
    @por_anuncio ||= insights.group(:ad_id).sum(:spend).transform_values { |valor| valor.to_f.round(2) }
  end

  def total
    @total ||= por_anuncio.values.sum.round(2)
  end

  # A moeda da conta de anúncios (nil quando não há gasto guardado).
  def moeda
    return @moeda if defined?(@moeda)

    @moeda = insights.where.not(currency: nil).pick(:currency)
  end

  def toques
    @toques ||= insights.sum(:link_clicks).to_i
  end

  private

  def conexao
    return @conexao if defined?(@conexao)

    conexao = Crm::MetaAdsConnection.active_for(@account.id)
    @conexao = conexao&.ad_account_id.present? ? conexao : nil
  end

  def insights
    return Crm::MetaAdInsightDaily.none if conexao.nil?

    Crm::MetaAdInsightDaily.where(account_id: @account.id, ad_account_id: conexao.ad_account_id, date: dias)
  end

  def dias
    @mes.range.begin.to_date..@mes.range.end.to_date
  end
end
