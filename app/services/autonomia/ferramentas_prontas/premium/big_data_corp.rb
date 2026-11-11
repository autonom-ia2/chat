# A CHAMADA À BIGDATACORP de uma consulta Premium (#2858, F7). Usa o cliente que a Prospecção já usa
# (`Prospecting::Research::BigDataCorpClient#query_route`): a mesma credencial da plataforma e os mesmos erros com
# código fechado. Credencial, token e o valor consultado nunca vão a log, erro nem resposta.
#
# Prazos (a chamada inteira cabe no prazo da consulta, e este no `timeout_seconds` da ferramenta e na folga do
# `HttpAssincronaJob`):
#   - uma tentativa de consulta (`max_provider_attempts: 1`): repetir um 5xx ou um timeout de consulta paga pode cobrar
#     duas vezes;
#   - uma tentativa de token, com prazo curto (`PRAZO_DO_TOKEN`);
#   - um teto da chamada inteira, token e consulta somados: o prazo do dataset (`Timeout.timeout`).
# O token vale para o processo enquanto não vence (`TOKENS`): a consulta seguinte não gera outro. A Prospecção segue
# com o token por instância do cliente (ela não passa `token_cache`).
# A resposta vira `Leitura` (encontrado, sem registro ou falha com motivo curto).
class Autonomia::FerramentasProntas::Premium::BigDataCorp < Autonomia::FerramentasProntas::Provedor
  NOME = 'bigdatacorp'.freeze
  HOST = 'plataforma.bigdatacorp.com.br'.freeze
  PRAZO_DO_TOKEN = 5
  Cliente = Autonomia::Prospecting::Research::BigDataCorpClient

  TOKENS = Autonomia::FerramentasProntas::Premium::Tokens.new

  def self.esquecer_token!
    TOKENS.write(nil)
  end

  # -> `Leitura`. Nunca levanta pelo que a BigDataCorp respondeu: falha de rede, de token, de status ou o teto da
  # chamada vira motivo. Sem a credencial na plataforma, nem o token guardado é usado: tirar a credencial para tudo.
  def ler(dataset, params)
    return falha('nao_configurada') unless Cliente.configured?

    resposta = Timeout.timeout(@prazo) do
      cliente.query_route(dataset.rota, query: dataset.busca.call(params), datasets: dataset.nome)
    end
    Autonomia::FerramentasProntas::Premium::Leitura.de(dataset, resposta.payload, id_na_fonte: resposta.metadata[:provider_request_id])
  rescue Cliente::Error => e
    falha(self.class.motivo_do_erro(e))
  rescue Timeout::Error
    falha('tempo_esgotado')
  end

  # O código fechado do cliente -> o motivo curto do contador (`bigdatacorp.http_504`). Nunca a mensagem de fora.
  def self.motivo_do_erro(erro)
    case erro.code
    when 'BIGDATACORP_TIMEOUT' then 'tempo_esgotado'
    when 'BIGDATACORP_NOT_CONFIGURED' then 'nao_configurada'
    when 'BIGDATACORP_HTTP_ERROR' then "http_#{erro.status.to_i}"
    when 'BIGDATACORP_DELIVERY_UNKNOWN' then 'entrega_incerta'
    when 'BIGDATACORP_PROVIDER_UNAVAILABLE' then 'indisponivel'
    else erro.phase.to_s == 'token' ? 'token' : 'falha'
    end
  end

  private

  def falha(motivo)
    Autonomia::FerramentasProntas::Premium::Leitura.falha(motivo)
  end

  def cliente
    Cliente.new(timeout: @prazo, token_timeout: PRAZO_DO_TOKEN, max_provider_attempts: 1, max_token_attempts: 1, token_cache: TOKENS)
  end
end
