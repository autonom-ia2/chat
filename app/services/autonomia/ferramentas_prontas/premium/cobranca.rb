# A COBRANÇA DE UMA CONSULTA PREMIUM (#2858, F7): decide se a consulta conta, se é grátis ou cobrada, e grava a
# telemetria (`Registro`). Não cobra nada: a fatura do mês sai da telemetria (decisão do Rodrigo, 10/11).
#
#   - conta: a que a BigDataCorp respondeu (encontrado ou sem registro), fora do cache;
#   - não conta: a falha (fonte lenta, 504, rede, token) e a que veio do cache;
#   - a contada recebe a posição no card da conta (`Saldo.contar!`): até 20, grátis; da 21ª em diante, cobrada pelo
#     preço do dataset (custo × 1,5). Um card não mexe no contador do outro.
# Depois de cada consulta com custo, confere o orçamento do mês (`Orcamento`).
module Autonomia::FerramentasProntas::Premium::Cobranca
  Premium = Autonomia::FerramentasProntas::Premium

  module_function

  # `resultado`: encontrado | sem_registro | falha. -> o `Registro` gravado.
  def registrar!(tool:, fonte:, consulta:, resultado:, do_cache: false, motivo: nil, id_na_fonte: nil) # rubocop:disable Metrics/ParameterLists
    contada = !do_cache && resultado != 'falha'
    numero = contada ? Premium::Saldo.contar!(account_id: tool.account_id, fonte: fonte.chave) : nil
    registro = Premium::Registro.create!(
      account_id: tool.account_id, autonomia_agent_id: tool.autonomia_agent_id, fonte: fonte.chave, consulta: consulta.nome,
      dataset: consulta.dataset.nome, dia: Time.zone.today, resultado: resultado, do_cache: do_cache, numero: numero,
      motivo: motivo, id_na_fonte: id_na_fonte, **valores(consulta.dataset, resultado, numero)
    )
    Premium::Orcamento.conferir! if registro.custo.positive?
    registro
  end

  def valores(dataset, resultado, numero)
    return { cobranca: 'sem_cobranca', custo: 0, preco: 0 } if numero.nil?
    return { cobranca: 'gratis', custo: dataset.custo_de(resultado), preco: 0 } if numero <= Premium::GRATIS

    { cobranca: 'cobrada', custo: dataset.custo_de(resultado), preco: dataset.preco }
  end
end
