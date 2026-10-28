# A guarda de custo da leitura automática (#2301), por conta.
#
# - Teto diário em dólares: TETO_DIARIO_USD; a ENV AUTONOMIA_DESEMPENHO_TETO_DIARIO_USD troca o padrão da instalação, e
#   a ficha (`configuracao.leitura.teto_diario_usd`) troca o da conta. O gasto é a soma do consumo gravado com a
#   feature da leitura desde o começo do dia no fuso da conta.
# - O teto é conferido antes de cada conversa, não reservado: a rodada pode passar dele em até uma conversa (a que
#   começou abaixo do teto). Os agentes da mesma conta não leem em paralelo (o orquestrador trava a conta e o job da
#   ficha se reagenda), então o excesso é de uma conversa por conta, não uma por agente. E o gasto vem do consumo
#   gravado na resposta: uma chamada que estoura o tempo depois de a OpenAI processar não grava consumo, e o gasto
#   fica menor que o cobrado.
# - Conversa grande demais: acima de MAX_CARACTERES na transcrição (ou `configuracao.leitura.max_caracteres`), a
#   conversa não vai ao modelo e fica como não lida.
class Autonomia::Desempenho::LeituraAutomatica::Teto
  TETO_DIARIO_USD = BigDecimal('1.00')
  MAX_CARACTERES = 400_000
  ENV_TETO = 'AUTONOMIA_DESEMPENHO_TETO_DIARIO_USD'.freeze

  def initialize(account:, ficha:)
    @account = account
    @leitura = ficha.configuracao['leitura'].is_a?(Hash) ? ficha.configuracao['leitura'] : {}
    @fuso = Autonomia::Desempenho::Painel.fuso_de(account, ficha)
  end

  def diario_usd
    @diario_usd ||= numero(@leitura['teto_diario_usd']) || numero(ENV.fetch(ENV_TETO, nil)) || TETO_DIARIO_USD
  end

  def gasto_hoje
    desde = Time.current.in_time_zone(@fuso).beginning_of_day
    Crm::AiUsageEvent.for_account(@account.id).where(feature: Autonomia::Desempenho::LeituraAutomatica::Leitor::FEATURE)
                     .since(desde).sum(:cost_estimate).to_d
  end

  def passou? = gasto_hoje >= diario_usd

  def max_caracteres = numero(@leitura['max_caracteres'])&.to_i || MAX_CARACTERES

  private

  # Número positivo, ou nil (vazio, texto que não é número, zero ou negativo).
  def numero(valor)
    decimal = BigDecimal(valor.to_s, exception: false)
    decimal if decimal&.positive?
  end
end
