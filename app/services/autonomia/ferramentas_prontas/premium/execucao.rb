# A EXECUÇÃO DE UMA CONSULTA PREMIUM (#2858, F7). A mesma ordem da `Execucao` das grátis — flag (a das prontas e a do
# Premium), acesso e corte da conta, consulta e parâmetros normalizados, o contador do dia (sem limite no Premium:
# decisão do Rodrigo, 11/11), cache —, e só muda o fim:
#   - o cache é da conta, até o fim do dia (`Premium::Cache`);
#   - a fonte é uma só, a BigDataCorp, sem reserva (`Premium::BigDataCorp`);
#   - cada desfecho vira uma linha de telemetria (`Premium::Cobranca`): encontrado, sem registro ("não havia
#     registro"), documento inválido recusado pela BigDataCorp (conta), falha (não conta) ou do cache (sem custo novo).
# O pedido que não serve (parâmetro fora do formato, um CPF no lugar do CNPJ, o CPF ou o CNPJ com dígito errado) é
# recusado antes: a BigDataCorp não é chamada, nada vai à telemetria e NÃO conta como consulta do cliente (decisão do
# Rodrigo, 11/11: "A, não conta"; o contador do dia, `Uso`, guarda o motivo). O documento que só a BigDataCorp recusa
# (-114) conta e é cobrado (`Leitura`).
class Autonomia::FerramentasProntas::Premium::Execucao < Autonomia::FerramentasProntas::Execucao
  Premium = Autonomia::FerramentasProntas::Premium
  INDICE_DA_EXECUCAO = 'idx_premium_consultas_tool_run'.freeze
  TELEMETRIA_FALHOU = 'premium.telemetria_falhou'.freeze

  # `tool_run_id`: a execução em segundo plano (`HttpAssincronaJob`), que vai à telemetria; nil no turno.
  def initialize(tool:, params: {}, tool_run_id: nil)
    super(tool: tool, params: params)
    @tool_run_id = tool_run_id
  end

  # O pedido saiu para a BigDataCorp? (O contrato do `HttpExecutor`, lido pela consulta em segundo plano.)
  def enviada?
    @chamou == true
  end

  private

  def novo_cache(params)
    Premium::Cache.new(@fonte, @consulta, params, conta: @tool.account_id)
  end

  # O documento inválido guardado no dia responde aqui; o encontrado e o sem registro, como nas grátis.
  def do_cache(params)
    texto = documento_invalido_do_cache || super
    cobrar(@cache.resultado_lido, do_cache: true) if texto
    texto
  end

  def documento_invalido_do_cache
    return unless @cache.ler.is_a?(Hash) && @cache.lido['situacao'] == Premium::Cache::DOCUMENTO_INVALIDO

    @provedor = 'cache'
    terminar(Autonomia::FerramentasProntas::Resposta.documento_invalido(@fonte, @consulta), desfecho: 'do_cache')
  end

  # A cobrança vem DEPOIS de montar a resposta: se a montagem levanta (defeito nosso), o cliente recebe "não consegui" e
  # não pode ficar com a consulta contada. A linha vira falha por defeito, com o nosso custo (a BigDataCorp respondeu),
  # e o defeito sobe ao rastreador pela `Execucao#call`.
  def consultar(params)
    @provedor = Premium::BigDataCorp::NOME
    @chamou = true
    leitura = Premium::BigDataCorp.new(nil, prazo: @consulta.prazo_por_fonte).ler(@consulta.dataset, @consulta.para_a_fonte(params))
    texto = montar(leitura, params)
    cobrar(leitura.situacao, motivo: leitura.motivo, id_na_fonte: leitura.id_na_fonte, custo_possivel: leitura.custo_possivel?)
    texto
  end

  def montar(leitura, params)
    responder(leitura, params)
  rescue StandardError
    cobrar('falha', motivo: 'defeito', id_na_fonte: leitura.id_na_fonte, custo_possivel: leitura.situacao != 'falha' || leitura.custo_possivel?)
    raise
  end

  # O cache do dia é gravado DEPOIS de montar: a montagem que levanta não deixa no cache um resultado que o cliente não
  # recebeu (a segunda consulta o leria como "do cache", sem cobrança; revisor, lote 3).
  def responder(leitura, params)
    case leitura.situacao
    when 'encontrado'
      entregar(leitura.dados, params, desfecho: nil).tap { @cache.encontrado(leitura.dados) }
    when 'sem_registro'
      terminar(Autonomia::FerramentasProntas::Resposta.nao_encontrado(@fonte, @consulta), desfecho: 'nao_encontradas')
        .tap { @cache.nao_encontrado }
    when 'documento_invalido'
      terminar(Autonomia::FerramentasProntas::Resposta.documento_invalido(@fonte, @consulta), desfecho: 'nao_encontradas',
                                                                                              motivos: ["#{@provedor}.documento_invalido"])
        .tap { @cache.documento_invalido }
    else
      terminar(Autonomia::FerramentasProntas::Resposta.nao_consegui, desfecho: 'sem_resposta', motivos: ["#{@provedor}.#{leitura.motivo}"])
    end
  end

  # A telemetria é a base da fatura, mas a resposta ao cliente não depende dela: a falha do banco ao gravar vai ao
  # rastreador e ao log (o contador volta atrás junto, na mesma transação). Outro erro é defeito nosso: levanta.
  # O log some e o rastreador está desligado em produção: o rastro durável é o motivo `premium.telemetria_falhou` no
  # contador do dia (`autonomia_ferramentas_prontas_usos.motivos`, por conta, card e dia). A conferência do dia lê ali:
  #   SELECT account_id, fonte, dia, motivos->>'premium.telemetria_falhou' AS falhas
  #   FROM autonomia_ferramentas_prontas_usos WHERE dia = CURRENT_DATE AND motivos ? 'premium.telemetria_falhou';
  # Com o banco inteiro fora, a marca também não grava: aí sobram o log e o rastreador.
  def cobrar(resultado, **)
    Premium::Cobranca.registrar!(tool: @tool, fonte: @fonte, consulta: @consulta, resultado: resultado, tool_run_id: @tool_run_id, **)
  rescue ActiveRecord::RecordNotUnique => e
    # A linha desta execução já existe: o varredor a fechou como entrega incerta (`Cobranca.entrega_incerta!`). Não é
    # defeito; a transação desfez a posição no saldo. Duplicidade em outro índice é defeito: levanta.
    raise unless e.message.include?(INDICE_DA_EXECUCAO)

    Rails.logger.info("#{PREFIXO} telemetria premium já fechada como entrega incerta conta=#{@tool.account_id} fonte=#{@fonte.chave}")
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("#{PREFIXO} telemetria premium falhou conta=#{@tool.account_id} fonte=#{@fonte.chave} #{e.class}")
    ChatwootExceptionTracker.new(e, account: @tool.account).capture_exception
    marcar_telemetria_falhou
  end

  def marcar_telemetria_falhou
    Autonomia::FerramentasProntas::Uso.anotar!(account_id: @tool.account_id, fonte: @fonte.chave, motivos: [TELEMETRIA_FALHOU])
  rescue StandardError => e
    Rails.logger.error("#{PREFIXO} marca da telemetria premium falhou conta=#{@tool.account_id} fonte=#{@fonte.chave} #{e.class}")
  end
end
