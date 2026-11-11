# A CHAMADA À BIGDATACORP de uma consulta Premium (#2858, F7). Usa o cliente que a Prospecção já usa
# (`Prospecting::Research::BigDataCorpClient#query_route`): a mesma credencial da plataforma, o mesmo token e os mesmos
# erros com código fechado. Credencial, token e o valor consultado nunca vão a log, erro nem resposta.
#
# Uma tentativa só (`max_provider_attempts: 1`): repetir um 5xx ou um timeout de consulta paga pode cobrar duas vezes.
# O prazo é o do dataset. A resposta vira `Leitura` (encontrado, sem registro ou falha com motivo curto).
class Autonomia::FerramentasProntas::Premium::BigDataCorp < Autonomia::FerramentasProntas::Provedor
  NOME = 'bigdatacorp'.freeze
  HOST = 'plataforma.bigdatacorp.com.br'.freeze
  Cliente = Autonomia::Prospecting::Research::BigDataCorpClient

  # -> `Leitura`. Nunca levanta pelo que a BigDataCorp respondeu: falha de rede, de token ou de status vira motivo.
  def ler(dataset, params)
    resposta = cliente.query_route(dataset.rota, query: dataset.busca.call(params), datasets: dataset.nome)
    Autonomia::FerramentasProntas::Premium::Leitura.de(dataset, resposta.payload, id_na_fonte: resposta.metadata[:provider_request_id])
  rescue Cliente::Error => e
    Autonomia::FerramentasProntas::Premium::Leitura.falha(self.class.motivo_do_erro(e))
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

  def cliente
    Cliente.new(timeout: @prazo, max_provider_attempts: 1)
  end
end
