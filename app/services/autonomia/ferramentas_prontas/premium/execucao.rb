# A EXECUÇÃO DE UMA CONSULTA PREMIUM (#2858, F7). A mesma ordem da `Execucao` das grátis — flag (a das prontas e a do
# Premium), acesso e corte da conta, consulta e parâmetros normalizados, o contador do dia (sem limite no Premium:
# decisão do Rodrigo, 11/11), cache —, e só muda o fim:
#   - o cache é da conta, até o fim do dia (`Premium::Cache`);
#   - a fonte é uma só, a BigDataCorp, sem reserva (`Premium::BigDataCorp`);
#   - cada desfecho vira uma linha de telemetria (`Premium::Cobranca`): encontrado, sem registro ("não havia
#     registro"), falha (não conta) ou do cache (sem custo novo).
# O pedido que não serve (parâmetro fora do formato, um CPF no lugar do CNPJ) é recusado antes: a BigDataCorp não é
# chamada e nada vai à telemetria (o contador do dia, `Uso`, guarda o motivo).
class Autonomia::FerramentasProntas::Premium::Execucao < Autonomia::FerramentasProntas::Execucao
  Premium = Autonomia::FerramentasProntas::Premium

  # O pedido saiu para a BigDataCorp? (O contrato do `HttpExecutor`, lido pela consulta em segundo plano.)
  def enviada?
    @chamou == true
  end

  private

  def novo_cache(params)
    Premium::Cache.new(@fonte, @consulta, params, conta: @tool.account_id)
  end

  def do_cache(params)
    texto = super
    cobrar(@cache.lido_sem_registro? ? 'sem_registro' : 'encontrado', do_cache: true) if texto
    texto
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
    else
      terminar(Autonomia::FerramentasProntas::Resposta.nao_consegui, desfecho: 'sem_resposta', motivos: ["#{@provedor}.#{leitura.motivo}"])
    end
  end

  # A telemetria é a base da fatura, mas a resposta ao cliente não depende dela: a falha do banco ao gravar vai ao
  # rastreador e ao log (o contador volta atrás junto, na mesma transação). Outro erro é defeito nosso: levanta.
  def cobrar(resultado, **)
    Premium::Cobranca.registrar!(tool: @tool, fonte: @fonte, consulta: @consulta, resultado: resultado, **)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("#{PREFIXO} telemetria premium falhou conta=#{@tool.account_id} fonte=#{@fonte.chave} #{e.class}")
    ChatwootExceptionTracker.new(e, account: @tool.account).capture_exception
  end
end
