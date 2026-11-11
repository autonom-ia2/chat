# O CACHE DAS CONSULTAS PREMIUM (#2858, F7): a mesma consulta, na mesma conta e no mesmo dia, vem daqui e não paga de
# novo. Diferente do cache das grátis, que é da fonte:
#   - é POR CONTA: a chave leva a conta, e uma conta nunca lê (nem economiza com) o que a outra pagou;
#   - vale até o fim do dia da conta (a `Execucao` roda no fuso dela), para o encontrado e para o sem registro, que
#     também foi contado.
# A chave continua com o HMAC dos parâmetros: quem lê o Redis não reverte o CNPJ, o CPF ou a placa.
class Autonomia::FerramentasProntas::Premium::Cache < Autonomia::FerramentasProntas::Cache
  DOCUMENTO_INVALIDO = 'documento_invalido'.freeze

  attr_reader :lido

  def initialize(fonte, consulta, params, conta:)
    super(fonte, consulta, params)
    @conta = conta
  end

  # Uma leitura por execução (o objeto é de uma consulta só): o documento inválido e o resto do cache leem o mesmo valor.
  def ler
    return @lido if @ja_lido

    @ja_lido = true
    @lido = super
  end

  def encontrado(dados, validade: nil) # rubocop:disable Lint/UnusedMethodArgument
    super(dados, validade: ate_o_fim_do_dia)
  end

  def nao_encontrado
    gravar({ 'situacao' => NAO_ENCONTRADO }, ate_o_fim_do_dia)
  end

  # O documento que a BigDataCorp recusou: contou uma vez, e o mesmo documento no mesmo dia não conta de novo.
  def documento_invalido
    gravar({ 'situacao' => DOCUMENTO_INVALIDO }, ate_o_fim_do_dia)
  end

  def chave
    "#{super.sub(':prontas:', ':premium:')}:conta-#{@conta.to_i}"
  end

  # O resultado da telemetria do que veio do cache: encontrado, sem_registro ou documento_invalido.
  def resultado_lido
    case @lido.is_a?(Hash) && @lido['situacao']
    when NAO_ENCONTRADO then 'sem_registro'
    when DOCUMENTO_INVALIDO then DOCUMENTO_INVALIDO
    else 'encontrado'
    end
  end

  private

  def ate_o_fim_do_dia
    agora = Time.zone.now
    [(agora.end_of_day - agora).ceil, 1].max.seconds
  end
end
