# Textos e números do relatório de Números › "De onde vieram os clientes" (#2001, F6): dinheiro e contagem do mesmo
# jeito do relatório de Anúncios (Advisor::Format), o mês por extenso e o filtro da tela ("Outubro de 2026, funil
# Vendas"), as datas no fuso da conta.
module Crm::Numeros::Origens::Relatorio::Formato
  SCOPE = 'numeros_origens_report'.freeze

  private

  def t(key, **)
    I18n.t("#{SCOPE}.#{key}", **)
  end

  def dinheiro(valor)
    Crm::MetaAds::Advisor::Format.value(:money, valor, locale: I18n.locale, currency: @dados.moeda) unless valor.nil?
  end

  def inteiro(valor)
    Crm::MetaAds::Advisor::Format.value(:count, valor, locale: I18n.locale)
  end

  def nome_do_mes
    data = @dados.mes
    t('month', month: t('months')[data.month - 1], year: data.year)
  end

  def filtro
    mes = nome_do_mes.upcase_first
    @dados.todos? ? t('filter_all', month: mes) : t('filter_pipeline', month: mes, pipeline: @dados.funil_nome)
  end

  def momento(valor)
    I18n.l(valor.in_time_zone(@dados.zona), format: '%d/%m/%Y %H:%M')
  end

  def nome_da_origem(tipo)
    t("origins.#{tipo}")
  end

  def nome_do_anuncio(anuncio)
    anuncio[:titulo].presence || t('ad_no_name')
  end

  def gerado_em
    @gerado_em ||= Time.current
  end

  def nome_do_arquivo(extensao)
    "#{t('file_prefix')}-#{@dados.mes.strftime('%Y-%m')}.#{extensao}"
  end
end
