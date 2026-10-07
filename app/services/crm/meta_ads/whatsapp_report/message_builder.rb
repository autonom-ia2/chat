# O texto do resumo e do alerta (#1100, F4b), no idioma da conta (pt_BR; en no config/locales).
#
# - WAHA: texto livre, uma linha por número (`summary_text`, `alert_text`).
# - Oficial: os mesmos números nas variáveis do modelo aprovado (`summary_parameters`, `alert_parameters`). O modelo
#   é sempre o pt_BR. A Meta recusa variável com quebra de linha, tab ou 4+ espaços seguidos (erro 132018), e o
#   nome do anúncio é texto livre vindo da Meta: toda variável sai numa linha só, com os espaços juntados.
#
# Valores com `number_to_currency` na moeda da conta; separadores e símbolo vêm do i18n de servidor.
class Crm::MetaAds::WhatsappReport::MessageBuilder
  SCOPE = 'meta_ads_whatsapp_report'.freeze
  DEFAULT_LOCALE = :pt_BR
  TEMPLATE_LOCALE = :pt_BR

  def initialize(account)
    @account = account
  end

  def summary_text(digest, test: false)
    I18n.with_locale(language) do
      lines = [summary_title(digest[:date], test), t('summary.spend', value: money(digest[:spend], digest[:currency])),
               conversations_line(digest), sales_line(digest), best_ad_line(digest[:best_ad]),
               t('summary.action', text: action_text(digest)), t('summary.link', url: panel_url)]
      lines.compact.join("\n")
    end
  end

  def alert_text(alert)
    I18n.with_locale(language) do
      [t('alert.text', name: alert[:name], value: money(alert[:spend], alert[:currency])), t('alert.hint', url: panel_url)].join("\n")
    end
  end

  def summary_parameters(digest, test: false)
    I18n.with_locale(TEMPLATE_LOCALE) do
      date = I18n.l(digest[:date], format: t('date_format'))
      date = "#{date} #{t('summary.test_prefix')}" if test
      # O modelo é pt_BR: o texto da IA só entra se foi escrito em pt_BR.
      action = language == TEMPLATE_LOCALE.to_s ? action_text(digest) : rule_text(digest)
      body([date, money(digest[:spend], digest[:currency]), results(digest), action])
    end
  end

  # O idioma da conta quando há texto do resumo nele; senão pt_BR. É também o idioma em que a IA escreve.
  def language
    account_locale = @account.locale.to_s
    I18n.exists?("#{SCOPE}.summary.title", account_locale) ? account_locale : DEFAULT_LOCALE.to_s
  end

  def alert_parameters(alert)
    I18n.with_locale(TEMPLATE_LOCALE) { body([alert[:name], money(alert[:spend], alert[:currency])]) }
  end

  private

  def t(key, **)
    I18n.t("#{SCOPE}.#{key}", **)
  end

  def summary_title(date, test)
    title = t('summary.title', date: I18n.l(date, format: t('date_format')))
    test ? "#{t('summary.test_prefix')} #{title}" : title
  end

  def conversations_line(digest)
    return t('summary.conversations', count: digest[:conversations]) if digest[:cost_per_conversation].nil?

    t('summary.conversations_with_cost', count: digest[:conversations], cost: money(digest[:cost_per_conversation], digest[:currency]))
  end

  def sales_line(digest)
    return t('summary.quotes_sales', quotes: digest[:quotes], sales: digest[:sales]) if digest[:sales].zero?

    t('summary.quotes_sales_value', quotes: digest[:quotes], sales: digest[:sales], value: money(digest[:sales_value], digest[:currency]))
  end

  def best_ad_line(best_ad)
    best_ad && t('summary.best_ad', name: best_ad[:name], count: best_ad[:conversations])
  end

  # "12 conversas, 3 propostas e 1 venda": uma variável só, para o modelo não ficar com variável demais para o texto.
  def results(digest)
    t('template.results', conversations: t('template.conversations', count: digest[:conversations]),
                          quotes: t('template.quotes', count: digest[:quotes]), sales: t('template.sales', count: digest[:sales]))
  end

  # O texto da IA quando há (título e como fazer, numa linha); senão a regra.
  def action_text(digest)
    ai = digest[:ai_action]
    return [ai[:headline], ai[:body]].compact.join(' ') if ai

    rule_text(digest)
  end

  # A ação da regra (Panel::Action).
  def rule_text(digest)
    rule = digest[:action]
    kind = rule[:kind]
    case kind
    when 'stalled_quotes'
      t('actions.stalled_quotes', count: rule[:count], days: rule[:days], value: money(rule[:value], digest[:currency]))
    when 'fix_tracking' then t('actions.fix_tracking', count: rule[:unknown])
    else t("actions.#{kind}")
    end
  end

  def money(value, currency)
    ActiveSupport::NumberHelper.number_to_currency(
      value.to_f, unit: t("currency_units.#{currency}", default: currency.to_s), format: '%u %n', precision: 2,
                  separator: t('number.separator'), delimiter: t('number.delimiter')
    )
  end

  def body(values)
    [{ type: 'body', parameters: values.map { |value| { type: 'text', text: value.to_s.split.join(' ') } } }]
  end

  def panel_url
    "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{@account.id}/campaigns/meta-ads?aba=resultado"
  end
end
