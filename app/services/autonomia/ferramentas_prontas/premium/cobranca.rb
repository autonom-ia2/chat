# A COBRANÇA DE UMA CONSULTA PREMIUM (#2858, F7): decide se a consulta conta, se é grátis ou cobrada, e grava a
# telemetria (`Registro`). Não cobra nada: a fatura do mês sai da telemetria (decisão do Rodrigo, 10/11).
#
#   - conta: a que a BigDataCorp respondeu (encontrado ou sem registro), fora do cache;
#   - não conta: a falha (fonte lenta, 504, rede, token) e a que veio do cache;
#   - a contada recebe a posição no card da conta no mês (`Saldo.contar!`): até 20, grátis; da 21ª do mês em diante,
#     cobrada pelo preço do dataset. As 20 grátis renovam todo mês (decisão do Rodrigo, 11/11). Um card não mexe no
#     contador do outro.
# O contador e a linha da telemetria andam juntos (uma transação): se a linha não grava, a posição volta atrás.
module Autonomia::FerramentasProntas::Premium::Cobranca
  Premium = Autonomia::FerramentasProntas::Premium

  module_function

  # `resultado`: encontrado | sem_registro | falha. Roda no fuso da conta (a `Execucao`). -> o `Registro` gravado.
  def registrar!(tool:, fonte:, consulta:, resultado:, do_cache: false, motivo: nil, id_na_fonte: nil) # rubocop:disable Metrics/ParameterLists
    contada = !do_cache && resultado != 'falha'
    hoje = Time.zone.today
    ActiveRecord::Base.transaction do
      numero = contada ? Premium::Saldo.contar!(account_id: tool.account_id, fonte: fonte.chave, mes: hoje.beginning_of_month) : nil
      Premium::Registro.create!(
        **origem(tool, fonte, consulta, hoje), resultado: resultado, do_cache: do_cache, numero: numero, motivo: motivo,
                                               id_na_fonte: id_na_fonte, **valores(consulta.dataset, resultado, numero)
      )
    end
  end

  # A consulta em segundo plano que morreu depois de a chamada sair (`HttpAssincronaJob.leitura_perdida`, com o
  # `ToolRun`): a BigDataCorp pode ter cobrado. Não conta para o cliente; o custo do dataset fica na telemetria, para a
  # conta bater com a fatura de lá. Pronta grátis: nada. A telemetria não segura o fechamento da linha: a falha do banco
  # vai ao rastreador e ao log.
  def entrega_incerta!(run)
    tool = run.ferramenta
    fonte = tool&.fonte_do_catalogo
    consulta = Premium.fonte?(fonte) && fonte.consulta(run.arguments.to_h['consulta'])
    return unless consulta

    Premium::Registro.create!(**origem(tool, fonte, consulta, Premium.hoje_da_conta(tool.account)),
                              resultado: 'falha', motivo: 'entrega_incerta', do_cache: false, numero: nil,
                              cobranca: 'sem_cobranca', custo: consulta.dataset.custo, preco: 0)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("[autonomia][premium] telemetria da entrega incerta falhou run=#{run.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: run.account).capture_exception
  end

  def origem(tool, fonte, consulta, dia)
    { account_id: tool.account_id, autonomia_agent_id: tool.autonomia_agent_id, fonte: fonte.chave, consulta: consulta.nome,
      dataset: consulta.dataset.nome, dia: dia }
  end

  def valores(dataset, resultado, numero)
    return { cobranca: 'sem_cobranca', custo: 0, preco: 0 } if numero.nil?
    return { cobranca: 'gratis', custo: dataset.custo_de(resultado), preco: 0 } if numero <= Premium::GRATIS

    { cobranca: 'cobrada', custo: dataset.custo_de(resultado), preco: dataset.preco }
  end
end
