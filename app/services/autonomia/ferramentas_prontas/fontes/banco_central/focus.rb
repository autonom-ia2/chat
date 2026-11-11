# O Boletim Focus no serviço Olinda do Banco Central: a mediana mais recente da expectativa do mercado para o ano atual e
# o seguinte (base de cálculo 0, a dos últimos 30 dias). A unidade da mediana vai em `unidades` (campo -> unidade).
class Autonomia::FerramentasProntas::Fontes::BancoCentral::Focus < Autonomia::FerramentasProntas::Provedor
  NOME = 'focus'.freeze
  HOST = 'olinda.bcb.gov.br'.freeze
  LINHAS = 6

  def consultar(_consulta, params)
    banco_central = Autonomia::FerramentasProntas::Fontes::BancoCentral
    indicador = params.fetch('indicador')
    nome = banco_central::INDICADORES.fetch(indicador)
    ano = Time.zone.today.year
    linhas = lista!(objeto!(get(caminho(nome, ano)))['value']).map { |item| objeto!(item) }
    anos = [ano, ano + 1].filter_map { |referencia| mais_recente(linhas, referencia) }
    { 'indicador' => "Focus: #{nome}", 'unidades' => { 'mediana' => banco_central::UNIDADES_DO_FOCUS.fetch(indicador) },
      'expectativas' => exigir!(anos) }
  end

  private

  def mais_recente(linhas, referencia)
    item = linhas.select { |linha| linha['DataReferencia'].to_s == referencia.to_s }.max_by { |linha| linha['Data'].to_s }
    return if item.nil?

    mediana = Autonomia::FerramentasProntas::Fontes::BancoCentral.numero(item['Mediana'])
    { 'ano' => referencia, 'mediana' => exigir!(mediana), 'data_do_boletim' => exigir!(texto(item['Data'])) }
  end

  def caminho(nome, ano)
    filtro = "Indicador eq '#{nome}' and baseCalculo eq 0 and (DataReferencia eq '#{ano}' or DataReferencia eq '#{ano + 1}')"
    '/olinda/servico/Expectativas/versao/v1/odata/ExpectativasMercadoAnuais' \
      "?%24filter=#{codificar(filtro)}&%24orderby=#{codificar('Data desc')}&%24top=#{LINHAS}" \
      "&%24select=#{codificar('Indicador,Data,DataReferencia,Mediana')}&%24format=json"
  end
end
