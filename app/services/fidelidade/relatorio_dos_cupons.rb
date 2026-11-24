# O relatório dos cupons da conta (#3100, aba Cupons): cada cupom com quantos códigos foram mandados, quantos foram
# usados e quanto venderam.
#
# Quanto vendeu (decisão D4 do Rodrigo, 23/11): a régua da F2 (CampaignJourney::ComprasNaJanela), as vendas fechadas da
# pessoa entre o uso do cupom e 7 dias depois, por moeda. Funis que a pessoa não vê nos relatórios ficam de fora, como
# no resultado da campanha. O valor só vai para quem vê valor de venda (Crm::ValorDeVenda, `sales_value_view`): sem
# ele, `vendas` é null e a tela mostra um traço.
class Fidelidade::RelatorioDosCupons
  JANELA_DIAS = 7

  def initialize(account, user:, account_user:)
    @account = account
    @com_valores = ::Crm::ValorDeVenda.ve?(account_user)
    visiveis = ::Crm::Access::VisiblePipelines.new(user: user, account: account, account_user: account_user)
    @pipeline_ids = visiveis.report_ids if visiveis.restricted?
  end

  def call
    cupons = Fidelidade::Cupom.da_conta(@account).order(created_at: :desc).to_a
    numeros = contagens(cupons.map(&:id))
    cupons.map { |cupom| linha(cupom, numeros[cupom.id]) }
  end

  # Um cupom só (o que acabou de ser criado, pausado ou ligado), no mesmo formato.
  def um(cupom) = linha(cupom, contagens([cupom.id])[cupom.id])

  private

  # { cupom_id => [mandados, usados] }, numa leitura só.
  def contagens(ids)
    Fidelidade::CupomCodigo.where(account_id: @account.id, cupom_id: ids).group(:cupom_id)
                           .pluck(:cupom_id, Arel.sql('COUNT(enviado_em)'), Arel.sql('COUNT(usado_em)'))
                           .to_h { |id, mandados, usados| [id, [mandados, usados]] }
  end

  def linha(cupom, numeros)
    mandados, usados = numeros || [0, 0]
    cupom.para_a_tela.merge(mandados: mandados, usados: usados, vendas: (vendas(cupom) if @com_valores))
  end

  # [{ moeda, total }] em reais, a maior primeiro; [] quando ninguém usou ou ninguém comprou.
  def vendas(cupom)
    usos = Fidelidade::CupomCodigo.where(account_id: @account.id, cupom_id: cupom.id).where.not(usado_em: nil)
                                  .pluck(:contact_id, :usado_em).to_h
    compras = ::CampaignJourney::ComprasNaJanela.new(@account, dias: JANELA_DIAS, pipeline_ids: @pipeline_ids).de(usos)
    ::CampaignJourney::ComprasNaJanela.valor(compras).map do |item|
      { moeda: item[:currency], total: item[:cents] / Fidelidade::TextoDoCupom::CENTAVOS.to_f }
    end
  end
end
