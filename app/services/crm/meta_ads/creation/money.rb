# Dinheiro do anúncio (#2198): nunca em float. O valor que a tela manda vira BigDecimal com no máximo 2 casas (mais que
# isso é recusa, nunca arredondamento) e vai para a Meta em centavos inteiros. A moeda é conferida na Meta antes de
# criar ou mudar: os limites (R$ 6 a R$ 500 por dia) são em reais, e conta em outra moeda não cria nem muda.
module Crm::MetaAds::Creation::Money
  CENTS = 100
  CURRENCY = 'BRL'.freeze

  # "45.5", 45.5 ou "45.50" → BigDecimal("45.5"). Vazio, texto, infinito ou mais de 2 casas → nil.
  def self.parse(value)
    amount = BigDecimal(value.to_s.strip, exception: false)
    amount if amount&.finite? && (amount * CENTS).frac.zero?
  end

  def self.cents(amount)
    (BigDecimal(amount.to_s) * CENTS).to_i
  end

  def self.from_cents(cents)
    BigDecimal(cents.to_i) / CENTS
  end

  # Para a tela e a Auditoria: texto decimal com 2 casas ("20.57", "20.00"), nunca float.
  def self.text(amount)
    whole, fraction = BigDecimal(amount.to_s).round(2).to_s('F').split('.')
    "#{whole}.#{fraction.to_s.ljust(2, '0')}"
  end

  # A moeda da conta de anúncios, lida na Meta. Falha na leitura é erro: sem moeda confirmada, nada de valor nem de criar.
  def self.currency!(client, ad_account_id)
    result = client.ad_account(ad_account_id)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok && result.data['currency'].present?

    result.data['currency'].to_s
  end
end
