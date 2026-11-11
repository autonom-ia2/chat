# O CACHE DAS CONSULTAS PREMIUM (#2858, F7): a mesma consulta, na mesma conta e no mesmo dia, vem daqui e não paga de
# novo. Diferente do cache das grátis, que é da fonte:
#   - é POR CONTA: a chave leva a conta, e uma conta nunca lê (nem economiza com) o que a outra pagou;
#   - vale até o fim do dia da conta (a `Execucao` roda no fuso dela), para o encontrado e para o sem registro, que
#     também foi contado.
# A chave continua com o HMAC dos parâmetros: quem lê o Redis não reverte o CNPJ, o CPF ou a placa.
class Autonomia::FerramentasProntas::Premium::Cache < Autonomia::FerramentasProntas::Cache
  attr_reader :lido

  def initialize(fonte, consulta, params, conta:)
    super(fonte, consulta, params)
    @conta = conta
  end

  def ler
    @lido = super
  end

  def encontrado(dados, validade: nil) # rubocop:disable Lint/UnusedMethodArgument
    super(dados, validade: ate_o_fim_do_dia)
  end

  def nao_encontrado
    gravar({ 'situacao' => NAO_ENCONTRADO }, ate_o_fim_do_dia)
  end

  def chave
    "#{super.sub(':prontas:', ':premium:')}:conta-#{@conta.to_i}"
  end

  # O que veio do cache era "sem registro"?
  def lido_sem_registro?
    @lido.is_a?(Hash) && @lido['situacao'] == NAO_ENCONTRADO
  end

  private

  def ate_o_fim_do_dia
    agora = Time.zone.now
    [(agora.end_of_day - agora).ceil, 1].max.seconds
  end
end
