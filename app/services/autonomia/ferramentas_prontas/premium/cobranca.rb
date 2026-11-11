# A COBRANÇA DE UMA CONSULTA PREMIUM (#2858, F7): decide se a consulta conta, se é grátis ou cobrada, e grava a
# telemetria (`Registro`). Não cobra nada: a fatura do mês sai da telemetria (decisão do Rodrigo, 10/11).
#
#   - conta: a que a BigDataCorp respondeu (encontrado ou sem registro), fora do cache;
#   - não conta: a falha (fonte lenta, 504, rede, token) e a que veio do cache. A falha com o pedido já no ar
#     (`custo_possivel`) leva o custo do dataset, sem contar nem cobrar: a telemetria bate com o painel da BigDataCorp;
#   - a contada recebe a posição no card da conta no mês (`Saldo.contar!`): até 20, grátis; da 21ª do mês em diante,
#     cobrada pelo preço do dataset. As 20 grátis renovam todo mês (decisão do Rodrigo, 11/11). Um card não mexe no
#     contador do outro.
# O contador e a linha da telemetria andam juntos (uma transação): se a linha não grava, a posição volta atrás. Na
# execução em segundo plano a linha leva o `tool_run_id`, único: uma linha por execução.
module Autonomia::FerramentasProntas::Premium::Cobranca
  Premium = Autonomia::FerramentasProntas::Premium

  module_function

  # `resultado`: encontrado | sem_registro | falha. Roda no fuso da conta (a `Execucao`). -> o `Registro` gravado.
  def registrar!(tool:, fonte:, consulta:, resultado:, do_cache: false, motivo: nil, id_na_fonte: nil, tool_run_id: nil, custo_possivel: false) # rubocop:disable Metrics/ParameterLists
    contada = !do_cache && resultado != 'falha'
    hoje = Time.zone.today
    ActiveRecord::Base.transaction(requires_new: true) do
      numero = contada ? Premium::Saldo.contar!(account_id: tool.account_id, fonte: fonte.chave, mes: hoje.beginning_of_month) : nil
      Premium::Registro.create!(
        **origem(tool, fonte, consulta, hoje), resultado: resultado, do_cache: do_cache, numero: numero, motivo: motivo,
                                               id_na_fonte: id_na_fonte, tool_run_id: tool_run_id,
                                               **valores(consulta.dataset, resultado, numero, custo_possivel: custo_possivel)
      )
    end
  end

  # A consulta em segundo plano que morreu depois de a chamada sair (`HttpAssincronaJob.leitura_perdida`, com o
  # `ToolRun`): a BigDataCorp pode ter cobrado, e o cliente não recebeu a resposta. Nada conta para o cliente; o custo
  # nosso fica na telemetria, para a conta bater com a fatura de lá. Numa transação:
  #   - a execução já gravou a linha dela (morreu entre a telemetria e o resultado): a linha vira `sem_cobranca`, a
  #     grátis volta ao saldo do mês e o preço zera; o custo fica. Nenhuma linha nova;
  #   - não gravou: uma linha de falha `entrega_incerta`, com o custo do dataset.
  # Pronta grátis: nada. A telemetria não segura o fechamento da linha: a falha do banco vai ao rastreador e ao log.
  def entrega_incerta!(run)
    tool = run.ferramenta
    fonte = tool&.fonte_do_catalogo
    consulta = Premium.fonte?(fonte) && fonte.consulta(run.arguments.to_h['consulta'])
    return unless consulta

    ActiveRecord::Base.transaction(requires_new: true) do
      gravada = Premium::Registro.lock.find_by(tool_run_id: run.id)
      next desfazer_cobranca!(gravada) if gravada
      # A execução viva pode gravar a linha dela entre a busca e a inserção: ON CONFLICT não insere, e a linha dela é
      # desfeita como a de cima.
      next if registrar_incerta!(run, tool, fonte, consulta)

      desfazer_cobranca!(Premium::Registro.lock.find_by!(tool_run_id: run.id))
    end
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("[autonomia][premium] telemetria da entrega incerta falhou run=#{run.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: run.account).capture_exception
  end

  # A FATURA LÊ `cobranca` ('cobrada' e o `preco` dela), NUNCA o `numero`. O número é a posição da consulta no mês na
  # hora em que contou, e deixa de ser único: a grátis desfeita baixa o contador, e a próxima consulta recebe de novo um
  # número que já existe; a cobrada convertida em grátis fica com o número acima de 20. Contar "numero > 20" erra a
  # fatura nos dois sentidos.
  def desfazer_cobranca!(registro)
    return if registro.cobranca == 'sem_cobranca'

    devolver_gratis!(registro) if registro.cobranca == 'gratis'
    registro.update!(cobranca: 'sem_cobranca', numero: nil, preco: 0, motivo: 'entrega_incerta')
  end

  # A grátis desfeita volta ao cliente. O contador baixa um (a consulta não contou). Com o mês já acima das 20, isso só
  # não basta: a próxima seguiria cobrada e o mês fecharia com 19 grátis. Então a cobrada mais antiga do mês, no mesmo
  # card e na mesma conta, vira a grátis que faltou (preço zero; o custo nosso fica). Tudo sob a trava do saldo.
  def devolver_gratis!(registro)
    mes = registro.dia.beginning_of_month
    saldo = Premium::Saldo.lock.find_by(account_id: registro.account_id, fonte: registro.fonte, mes: mes)
    return unless saldo&.contadas&.positive?

    converter_cobrada_mais_antiga!(registro, mes) if saldo.contadas > Premium::GRATIS
    saldo.update!(contadas: saldo.contadas - 1)
  end

  # O `FOR UPDATE` com ORDER BY e LIMIT volta vazio quando a linha que ele esperava muda de estado enquanto espera (outra
  # entrega incerta desfazendo aquela cobrada): o Postgres reavalia a linha travada e não busca a seguinte. Com o mês
  # acima das 20, vazio é essa corrida; cada busca nova roda num retrato novo (READ COMMITTED) e acha a seguinte. Sem
  # nenhuma cobrada depois das tentativas, o contador baixa assim mesmo e o caso vai ao log.
  TENTATIVAS_DA_CONVERSAO = 3

  def converter_cobrada_mais_antiga!(registro, mes)
    TENTATIVAS_DA_CONVERSAO.times do
      cobrada = cobrada_mais_antiga(registro, mes)
      return cobrada.update!(cobranca: 'gratis', preco: 0) if cobrada
    end
    Rails.logger.warn("[autonomia][premium] sem cobrada para converter na grátis devolvida conta=#{registro.account_id} fonte=#{registro.fonte}")
  end

  def cobrada_mais_antiga(registro, mes)
    Premium::Registro.lock.where(account_id: registro.account_id, fonte: registro.fonte, dia: mes..mes.end_of_month, cobranca: 'cobrada')
                     .order(:numero, :id).first
  end

  # INSERT ... ON CONFLICT (tool_run_id) DO NOTHING. -> true quando inseriu. Os valores são fixos daqui (resultado,
  # cobrança e motivo das listas do `Registro`), por isso sem as validações do modelo.
  def registrar_incerta!(run, tool, fonte, consulta)
    linha = origem(tool, fonte, consulta, Premium.hoje_da_conta(tool.account)).merge(
      resultado: 'falha', motivo: 'entrega_incerta', do_cache: false, numero: nil, tool_run_id: run.id, cobranca: 'sem_cobranca',
      custo: consulta.dataset.custo, preco: 0
    )
    Premium::Registro.insert_all([linha], unique_by: :idx_premium_consultas_tool_run, returning: [:id]).rows.any? # rubocop:disable Rails/SkipsModelValidations
  end

  def origem(tool, fonte, consulta, dia)
    { account_id: tool.account_id, autonomia_agent_id: tool.autonomia_agent_id, fonte: fonte.chave, consulta: consulta.nome,
      dataset: consulta.dataset.nome, dia: dia }
  end

  # Sem número (cache ou falha): nada para o cliente; o custo nosso só na falha com o pedido já no ar.
  def valores(dataset, resultado, numero, custo_possivel: false)
    return { cobranca: 'sem_cobranca', custo: custo_sem_numero(dataset, resultado, custo_possivel), preco: 0 } if numero.nil?
    return { cobranca: 'gratis', custo: dataset.custo_de(resultado), preco: 0 } if numero <= Premium::GRATIS

    { cobranca: 'cobrada', custo: dataset.custo_de(resultado), preco: dataset.preco }
  end

  def custo_sem_numero(dataset, resultado, custo_possivel)
    resultado == 'falha' ? dataset.custo_de(resultado, custo_possivel: custo_possivel) : 0
  end
end
