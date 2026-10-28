# A guarda de custo da leitura automática (#2301), por conta.
#
# - Teto diário em dólares, da CONTA: TETO_DIARIO_USD; a ENV AUTONOMIA_DESEMPENHO_TETO_DIARIO_USD troca o padrão da
#   instalação, e a ficha (`configuracao.leitura.teto_diario_usd`) troca o do agente. Como o gasto somado é o da conta
#   inteira, vale o MENOR teto entre as fichas vigentes com chave de leitura da conta: uma ficha com teto alto não
#   libera gasto para as outras. O gasto é a soma do consumo gravado com a feature da leitura desde o começo do dia no
#   fuso da conta.
# - O teto é conferido antes de cada conversa, não reservado: a rodada pode passar dele em até uma conversa (a que
#   começou abaixo do teto). Os agentes da mesma conta não leem em paralelo (o orquestrador trava a conta e o job da
#   ficha se reagenda), então o excesso é de uma conversa por conta, não uma por agente. E o gasto vem do consumo
#   gravado na resposta: uma chamada que estoura o tempo depois de a OpenAI processar não grava consumo, e o gasto
#   fica menor que o cobrado (a conversa que estoura o tempo de novo sai da fila pelo VezesDaConversa, então isso não
#   se repete para sempre).
# - Conversa grande demais: acima de MAX_CARACTERES na transcrição (ou `configuracao.leitura.max_caracteres`), a
#   conversa não vai ao modelo e fica como não lida.
class Autonomia::Desempenho::LeituraAutomatica::Teto
  TETO_DIARIO_USD = BigDecimal('1.00')
  MAX_CARACTERES = 400_000
  ENV_TETO = 'AUTONOMIA_DESEMPENHO_TETO_DIARIO_USD'.freeze

  def initialize(account:, ficha:)
    @account = account
    @ficha = ficha
    @leitura = leitura_de(ficha)
    @fuso = Autonomia::Desempenho::Painel.fuso_de(account, ficha)
  end

  def diario_usd
    @diario_usd ||= ([teto_da(@leitura)] + outras_fichas.map { |ficha| teto_da(leitura_de(ficha)) }).min
  end

  def gasto_hoje
    desde = Time.current.in_time_zone(@fuso).beginning_of_day
    Crm::AiUsageEvent.for_account(@account.id).where(feature: Autonomia::Desempenho::LeituraAutomatica::Leitor::FEATURE)
                     .since(desde).sum(:cost_estimate).to_d
  end

  def passou? = gasto_hoje >= diario_usd

  def max_caracteres = numero(@leitura['max_caracteres'])&.to_i || MAX_CARACTERES

  private

  def leitura_de(ficha) = ficha.configuracao['leitura'].is_a?(Hash) ? ficha.configuracao['leitura'] : {}

  def teto_da(leitura) = numero(leitura['teto_diario_usd']) || numero(ENV.fetch(ENV_TETO, nil)) || TETO_DIARIO_USD

  # As fichas vigentes com chave de leitura dos outros agentes da conta que entram na leitura (Elegivel): o agente
  # apagado ou desligado não lê, e o teto dele não vale.
  def outras_fichas
    sujeitos = Autonomia::Desempenho::Ficha.where(account_id: @account.id).where.not(chave_de_leitura: [nil, ''])
                                           .distinct.pluck(:sujeito_type, :sujeito_id) - [[@ficha.sujeito_type, @ficha.sujeito_id]]
    sujeitos.filter_map do |tipo, id|
      next unless Autonomia::Desempenho::LeituraAutomatica::Elegivel.sujeito?(@account, tipo, id)

      ficha = Autonomia::Desempenho::Ficha.vigente(@account, tipo, id)
      ficha if ficha&.chave_de_leitura.present?
    end
  end

  # Número positivo, ou nil (vazio, texto que não é número, zero ou negativo).
  def numero(valor)
    decimal = BigDecimal(valor.to_s, exception: false)
    decimal if decimal&.positive?
  end
end
