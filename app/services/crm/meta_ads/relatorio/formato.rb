# Textos e números do relatório baixado de Anúncios (#1960): dinheiro, contagem e duração do mesmo jeito do consultor
# (Advisor::Format), datas no fuso da conta e a situação de cada pessoa com a mesma regra da tela.
module Crm::MetaAds::Relatorio::Formato
  SCOPE = 'meta_ads_report'.freeze

  private

  def t(key, **)
    I18n.t("#{SCOPE}.#{key}", **)
  end

  def dinheiro(valor, moeda)
    Crm::MetaAds::Advisor::Format.value(:money, valor, locale: I18n.locale, currency: moeda)
  end

  def inteiro(valor)
    Crm::MetaAds::Advisor::Format.value(:count, valor, locale: I18n.locale)
  end

  def duracao(segundos)
    Crm::MetaAds::Advisor::Format.value(:duration, segundos, locale: I18n.locale)
  end

  def dia(data)
    I18n.l(data.to_date, format: '%d/%m/%Y')
  end

  def momento(valor, zona)
    I18n.l(valor.in_time_zone(zona), format: '%d/%m/%Y %H:%M')
  end

  # Venda e perda marcadas no card valem primeiro; depois quem ainda espera resposta; o resto está conversando.
  def situacao(item)
    return :bought if item[:status] == 'won'
    return :lost if item[:status] == 'lost'

    item[:answered] == false ? :no_answer : :talking
  end

  # Propostas ainda sem venda.
  def abertas(anuncio)
    [anuncio[:quotes].to_i - anuncio[:sales].to_i, 0].max
  end

  def nome_do_anuncio(anuncio)
    anuncio[:name].presence || t('ad_no_name')
  end
end
