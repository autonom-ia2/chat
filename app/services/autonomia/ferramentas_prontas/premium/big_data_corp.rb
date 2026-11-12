# A CHAMADA À BIGDATACORP de uma consulta Premium (#2858, F7). Usa o cliente que a Prospecção já usa
# (`Prospecting::Research::BigDataCorpClient#query_route`): a mesma credencial da plataforma e os mesmos erros com
# código fechado. Credencial, token e o valor consultado nunca vão a log, erro nem resposta.
#
# Prazos (a chamada inteira cabe no prazo da consulta, e este no `timeout_seconds` da ferramenta e na folga do
# `HttpAssincronaJob`):
#   - uma tentativa de consulta (`max_provider_attempts: 1`): repetir um 5xx ou um timeout de consulta paga pode cobrar
#     duas vezes;
#   - uma tentativa de token, com prazo curto (`PRAZO_DO_TOKEN`);
#   - um teto da chamada inteira, token e consulta somados: o prazo do dataset (`Timeout.timeout`), até 120 s nas lentas
#     (`Dataset::PRAZO_DAS_LENTAS`, #2946). O token sai do mesmo teto: com o token guardado (o normal), a consulta tem o
#     prazo inteiro; sem ele, o pedido do token come até `PRAZO_DO_TOKEN` por operação, e o que passar disso vira
#     `tempo_esgotado` (custo possível só se a consulta já tinha saído, `query_dispatched?`).
# A ferramenta incluída antes do #2946 guarda o `timeout_seconds` do prazo antigo (23 s no Raio-X e no Contato). A
# execução Premium não lê esse número (o prazo é o do catálogo); ele só marca quando a linha da execução em segundo
# plano vence (`HttpAssincronaJob.vence_em`: o número mais 2 minutos de folga, contados de quando o job começa), e 23 s
# mais 2 minutos passa dos 122 s da consulta. A incluída depois já nasce com 123 s (`Incluir`).
# O token vale para o processo enquanto não vence (`TOKENS`): a consulta seguinte não gera outro. O 401 apaga o token
# guardado e permite um reenvio com token novo (a BigDataCorp não cobra o 401). A Prospecção segue com o token por
# instância do cliente e sem o reenvio extra (ela não passa `token_cache` nem `resend_after_unauthorized`).
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

    @cliente = novo_cliente
    resposta = Timeout.timeout(@prazo) do
      @cliente.query_route(dataset.rota, query: dataset.busca.call(params), datasets: dataset.nome)
    end
    Autonomia::FerramentasProntas::Premium::Leitura.de(dataset, resposta.payload, id_na_fonte: resposta.metadata[:provider_request_id])
  rescue Cliente::Error => e
    falha(self.class.motivo_do_erro(e), custo_possivel: self.class.pedido_saiu?(e))
  rescue Timeout::Error
    # O teto da chamada inteira (token e consulta somados). O `PRAZO_DO_TOKEN` vale POR OPERAÇÃO (abrir, SSL, enviar e
    # ler: até 4 x 5 s, mais o token de novo depois do 401), e o teto pode estourar ainda no token: só custa se a
    # consulta já tinha saído dele (`query_dispatched?`).
    falha('tempo_esgotado', custo_possivel: @cliente.query_dispatched?)
  end

  # A rede que falhou antes de o pedido sair (a causa do `BIGDATACORP_DELIVERY_UNKNOWN` do cliente): o nome que não
  # resolveu, a conexão recusada, a rede ou o host fora de alcance. O SSL entra só no aperto de mão (`SSL_connect`, o
  # texto fixo do OpenSSL); o SSL que cai no meio da leitura pode ter levado o pedido.
  NAO_SAIU = [SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH].freeze
  APERTO_DE_MAO_DO_SSL = 'SSL_connect'.freeze

  # O pedido da consulta saiu e a BigDataCorp pode ter cobrado? A entrega incerta (a conexão que caiu depois de aberta:
  # ECONNRESET, EPIPE, EOFError; ou o 200 sem JSON, sem causa) e o tempo esgotado esperando a resposta. A conexão que nem
  # abriu (`Net::OpenTimeout`, ou um erro de `NAO_SAIU`) não saiu; o erro de token, de configuração e o HTTP de erro
  # também não cobram.
  def self.pedido_saiu?(erro)
    return !conexao_nao_abriu?(erro.cause) if erro.code == 'BIGDATACORP_DELIVERY_UNKNOWN'

    erro.code == 'BIGDATACORP_TIMEOUT' && !erro.cause.is_a?(Net::OpenTimeout)
  end

  def self.conexao_nao_abriu?(causa)
    return true if NAO_SAIU.any? { |classe| causa.is_a?(classe) }

    causa.is_a?(OpenSSL::SSL::SSLError) && causa.message.to_s.start_with?(APERTO_DE_MAO_DO_SSL)
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

  def falha(motivo, custo_possivel: false)
    Autonomia::FerramentasProntas::Premium::Leitura.falha(motivo, custo_possivel: custo_possivel)
  end

  def novo_cliente
    Cliente.new(timeout: @prazo, token_timeout: PRAZO_DO_TOKEN, max_provider_attempts: 1, max_token_attempts: 1, token_cache: TOKENS,
                resend_after_unauthorized: true)
  end
end
