# A formatação única dos campos do catálogo (#1331): pt-BR, no fuso da conta, decidida pelo tipo do campo.
#   data  14/10/2026        hora  15:00        moeda  R$ 1.250,00
#
# Valor de coluna da planilha só é reformatado quando veio em forma de máquina: a data ISO que a leitura do XLSX
# devolve (CampaignImports::CellValues.excel_serial) e o número simples ("1234.5"). O que a pessoa escreveu do jeito
# dela ("10/2026", "R$ 1.234,50") vai como está: nada é adivinhado.
module TemplateFields::Format
  DATE = '%d/%m/%Y'.freeze
  TIME = '%H:%M'.freeze
  BRL = 'BRL'.freeze
  BRL_UNIT = 'R$'.freeze
  ISO_DATE_LENGTH = 10
  ISO_TIME_LENGTH = 5
  # "1.234" é mil e duzentos e trinta e quatro em pt-BR e 1,234 em inglês: três casas depois do ponto ficam como estão.
  AMBIGUOUS_FRACTION = 3

  module_function

  def account_zone(account)
    Crm::Timezone::Resolver.new(account: account).zone_or_default
  end

  def date(value, zone)
    value&.in_time_zone(zone)&.strftime(DATE)
  end

  def time(value, zone)
    value&.in_time_zone(zone)&.strftime(TIME)
  end

  def money_cents(cents, currency = BRL)
    cents.nil? ? nil : money(BigDecimal(cents.to_i) / 100, currency)
  end

  def money(amount, currency = BRL)
    code = currency.to_s.upcase.presence || BRL
    ActiveSupport::NumberHelper.number_to_currency(
      amount, unit: code == BRL ? BRL_UNIT : code, separator: ',', delimiter: '.', precision: 2,
              format: '%u %n', negative_format: '-%u %n'
    )
  end

  # O valor de uma coluna extra do Público, pelo tipo da coluna; vazio vira nil.
  def audience_value(value, type)
    text = value.to_s.squish
    formatted = case type
                when 'data' then iso_date(text)
                when 'moeda' then plain_amount(text)
                end
    (formatted || text).presence
  end

  # "2026-10-14" ou "2026-10-14 15:00" (a leitura do XLSX) => "14/10/2026" ou "14/10/2026 15:00".
  def iso_date(text)
    date_part, time_part = text.split(' ', 2)
    return unless iso_date_shape?(date_part.to_s) && (time_part.nil? || iso_time_shape?(time_part))

    [Date.iso8601(date_part).strftime(DATE), time_part].compact.join(' ')
  rescue Date::Error
    nil
  end

  def iso_date_shape?(text)
    text.length == ISO_DATE_LENGTH && text[4] == '-' && text[7] == '-' && digits?(text.delete('-'))
  end

  def iso_time_shape?(text)
    text.length == ISO_TIME_LENGTH && text[2] == ':' && digits?(text.delete(':'))
  end

  # "1234.5" ou "-80" => R$; qualquer outra escrita fica como está.
  def plain_amount(text)
    whole, fraction, extra = text.delete_prefix('-').split('.', -1)
    return if extra || !digits?(whole.to_s)
    return if fraction && (!digits?(fraction) || fraction.length == AMBIGUOUS_FRACTION)

    money(BigDecimal(text))
  end

  def digits?(text)
    !text.empty? && text.each_char.all? { |char| char.between?('0', '9') }
  end
end
