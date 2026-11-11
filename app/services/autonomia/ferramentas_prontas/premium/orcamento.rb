# O ORÇAMENTO DO MÊS DAS CONSULTAS PREMIUM (#2858, F7): quanto a plataforma aceita pagar à BigDataCorp por mês, em
# reais, somando todas as contas. Passou de 80%, a equipe recebe UM alerta no mês (e-mail ao administrador da
# instalação, `CHATWOOT_INSTANCE_ADMIN_EMAIL`, e o log `[autonomia][premium] orcamento_80`). O alerta não corta nada.
#
# A configuração é da instalação: `AUTONOMIA_PREMIUM_ORCAMENTO_MENSAL` (Super Admin, ou a variável de ambiente), em
# reais. Vazia ou inválida: o padrão `PADRAO`. O custo é o da telemetria (`Registro#custo`), o que a BigDataCorp cobra
# de nós, não o preço da fatura. A conta da BigDataCorp é a mesma da Cotação e da Prospecção: este orçamento cobre só o
# Premium.
module Autonomia::FerramentasProntas::Premium::Orcamento
  CONFIG = 'AUTONOMIA_PREMIUM_ORCAMENTO_MENSAL'.freeze
  PADRAO = BigDecimal(500)
  LIMIAR = BigDecimal('0.8')
  CHAVE_DO_ALERTA = 'autonomia:premium:alerta_do_orcamento'.freeze
  VALIDADE_DO_ALERTA = 40.days
  ERROS_DE_INFRA = [Redis::BaseError, RedisClient::Error, ActiveRecord::ActiveRecordError].freeze

  module_function

  def valor
    bruto = configurado.presence || ENV.fetch(CONFIG, nil)
    numero = BigDecimal(bruto.to_s.strip.tr(',', '.'), exception: false)
    numero&.positive? ? numero : PADRAO
  end

  def configurado
    GlobalConfig.get(CONFIG)[CONFIG]
  rescue *ERROS_DE_INFRA => e
    Rails.logger.warn("[autonomia][premium] configuração do orçamento indisponível #{e.class}")
    nil
  end

  def gasto_do_mes(hoje = Time.zone.today)
    Autonomia::FerramentasProntas::Premium::Registro.where(dia: hoje.all_month).sum(:custo)
  end

  # Depois de cada consulta que custou: passou de 80% e ainda não avisou neste mês -> avisa uma vez.
  def conferir!(hoje = Time.zone.today)
    orcamento = valor
    gasto = gasto_do_mes(hoje)
    return false if gasto < orcamento * LIMIAR
    return false unless primeiro_aviso_do_mes?(hoje)

    avisar(gasto, orcamento, hoje)
    true
  end

  def primeiro_aviso_do_mes?(hoje)
    Redis::Alfred.with { |conn| conn.set("#{CHAVE_DO_ALERTA}:#{hoje.strftime('%Y-%m')}", 1, nx: true, ex: VALIDADE_DO_ALERTA.to_i) }
  end

  def avisar(gasto, orcamento, hoje)
    mes = hoje.strftime('%m/%Y')
    Rails.logger.warn("[autonomia][premium] orcamento_80 mes=#{mes} gasto=#{gasto.to_s('F')} orcamento=#{orcamento.to_s('F')}")
    AdministratorNotifications::PremiumMailer.with(gasto: gasto.to_s('F'), orcamento: orcamento.to_s('F'), mes: mes)
                                             .orcamento_do_mes.deliver_later
  end
end
