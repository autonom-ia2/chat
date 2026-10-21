# A gaveta "Metas do mês" de CRM › Números (#1991, F4 do #1871), no formato do adaptador falso do protótipo aprovado
# (proto/1871-numeros, crmNumerosFalso.js#metas): uma aba por funil de Vender, a meta do funil e uma linha por pessoa
# com a meta do mês, a do mês anterior (atalho "Repetir") e a sugestão com o motivo (o que ela vendeu nos 3 meses
# fechados anteriores). Valores em reais inteiros, na moeda do funil.
class Crm::Metas::Gaveta
  MESES_DE_HISTORICO = 3
  PASSO_GRANDE = 500
  A_PARTIR_DE = 1000

  def initialize(account:, user:, account_user:)
    @account = account
    @mes = Crm::Numeros::Mes.new(account: account)
    @escopo = Crm::Metas::Escopo.new(account: account, user: user, account_user: account_user, mes: @mes)
  end

  def perform
    { mes: chave(@mes.inicio), mesAnterior: chave(@mes.inicio.prev_month), funis: @escopo.funis.map { |funil| funil_de(funil) } }
  end

  # Sugestão: a média dos meses, de R$ 500 em R$ 500 a partir de R$ 1.000. Sem venda nenhuma, nenhuma sugestão.
  def self.sugerir(historico)
    media = historico.sum.to_f / historico.size
    return nil if media.zero?

    passo = media >= A_PARTIR_DE ? PASSO_GRANDE : 1
    ((media / passo).round * passo).to_i
  end

  private

  def chave(momento)
    momento.strftime('%Y-%m')
  end

  def funil_de(funil)
    moeda = Crm::Metas::Escopo.moeda_de(funil)
    {
      id: funil.id, nome: funil.name, medida: 'valor', moeda: moeda, metaFunil: meta_do_funil(funil, moeda),
      pessoas: @escopo.pessoas_de(funil).map { |pessoa| pessoa_de(funil, pessoa, moeda) }
    }
  end

  def meta_do_funil(funil, moeda)
    goals = (funil.metadata || {})['goals'] || {}
    cents = goals['monthly_target_cents'].to_i
    cents.positive? && (goals['currency'].presence || 'BRL') == moeda ? reais(cents) : nil
  end

  def pessoa_de(funil, pessoa, moeda)
    historico = meses_fechados.map { |vendido| reais(vendido[[funil.id, pessoa.id, moeda]]) }
    {
      id: pessoa.id, nome: pessoa.name, meta: meta(funil, pessoa, @escopo.mes_do_banco),
      anterior: meta(funil, pessoa, @escopo.mes_do_banco.prev_month),
      sugestao: { valor: self.class.sugerir(historico), historico: historico }
    }
  end

  def meta(funil, pessoa, mes)
    cents = metas[[funil.id, pessoa.id, mes]]
    cents ? reais(cents) : nil
  end

  def metas
    @metas ||= Crm::PersonGoal.where(account_id: @account.id, pipeline_id: @escopo.funis.map(&:id),
                                     month: [@escopo.mes_do_banco, @escopo.mes_do_banco.prev_month])
                              .pluck(:pipeline_id, :user_id, :month, :target_cents)
                              .to_h { |funil, pessoa, mes, cents| [[funil, pessoa, mes], cents] }
  end

  # Do mais antigo para o mais recente, como o motivo diz ("fechou h1, h2 e h3").
  def meses_fechados
    @meses_fechados ||= MESES_DE_HISTORICO.downto(1).map do |atras|
      inicio = @mes.inicio - atras.months
      Crm::Metas::Vendido.new(account: @account, range: inicio..inicio.end_of_month).por_pessoa
    end
  end

  def reais(cents)
    (cents.to_i / 100.0).round
  end
end
