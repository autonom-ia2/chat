# As séries do SGS do Banco Central (principal da Selic e do IPCA; reserva do dólar). Cada série: o último valor.
class Autonomia::FerramentasProntas::Fontes::BancoCentral::Sgs < Autonomia::FerramentasProntas::Provedor
  NOME = 'sgs'.freeze
  HOST = 'api.bcb.gov.br'.freeze
  SELIC = 432
  IPCA_NO_MES = 433
  IPCA_EM_12_MESES = 13_522
  DOLAR_VENDA = 1
  DOLAR_COMPRA = 10_813

  def consultar(consulta, _params)
    banco = Autonomia::FerramentasProntas::Fontes::BancoCentral
    case consulta.nome
    when 'selic' then banco.selic(ultimo(SELIC).last)
    when 'ipca' then ipca(banco)
    when 'dolar' then dolar(banco)
    end
  rescue Date::Error
    raise Falha, 'resposta_invalida'
  end

  private

  def ipca(banco)
    data, no_mes = ultimo(IPCA_NO_MES)
    banco.ipca(mes: data[3, 7], no_mes: no_mes, em_12_meses: ultimo(IPCA_EM_12_MESES).last)
  end

  def dolar(banco)
    data, venda = ultimo(DOLAR_VENDA)
    data_da_compra, compra = ultimo(DOLAR_COMPRA)
    # Compra e venda do mesmo boletim; de dias diferentes, o par não serve.
    raise Falha, 'resposta_invalida' unless data_da_compra == data

    banco.dolar(compra: compra, venda: venda, data: Date.strptime(data, '%d/%m/%Y').iso8601)
  end

  # -> [data "dd/mm/aaaa", valor]. Data fora do formato: `Date::Error`, que vira falha da fonte (`consultar`).
  def ultimo(serie)
    item = objeto!(exigir!(lista!(get("/dados/serie/bcdata.sgs.#{serie.to_i}/dados/ultimos/1?formato=json"))).last)
    valor = Autonomia::FerramentasProntas::Fontes::BancoCentral.numero(item['valor'])
    [exigir!(texto(item['data'])), exigir!(valor)]
  end
end
