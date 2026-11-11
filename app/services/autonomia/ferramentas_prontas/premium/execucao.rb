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

  def consultar(params)
    @provedor = Premium::BigDataCorp::NOME
    @chamou = true
    leitura = Premium::BigDataCorp.new(nil, prazo: @consulta.prazo_por_fonte).ler(@consulta.dataset, @consulta.para_a_fonte(params))
    cobrar(leitura.situacao, motivo: leitura.motivo, id_na_fonte: leitura.id_na_fonte)
    responder(leitura, params)
  end

  def responder(leitura, params)
    case leitura.situacao
    when 'encontrado'
      @cache.encontrado(leitura.dados)
      entregar(leitura.dados, params, desfecho: nil)
    when 'sem_registro'
      @cache.nao_encontrado
      terminar(Autonomia::FerramentasProntas::Resposta.nao_encontrado(@fonte, @consulta), desfecho: 'nao_encontradas')
    when 'documento_invalido'
      @cache.documento_invalido
      terminar(Autonomia::FerramentasProntas::Resposta.documento_invalido(@fonte, @consulta), desfecho: 'nao_encontradas',
                                                                                              motivos: ["#{@provedor}.documento_invalido"])
    else
      terminar(Autonomia::FerramentasProntas::Resposta.nao_consegui, desfecho: 'sem_resposta', motivos: ["#{@provedor}.#{leitura.motivo}"])
    end
  end

  # A telemetria é a base da fatura, mas a resposta ao cliente não depende dela: a falha do banco ao gravar vai ao
  # rastreador e ao log (o contador volta atrás junto, na mesma transação). Outro erro é defeito nosso: levanta.
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
  end
end
