# A PTAX do dólar no serviço Olinda do Banco Central (principal do dólar): o último boletim dos últimos dez dias
# (cobre fim de semana e feriado).
class Autonomia::FerramentasProntas::Fontes::BancoCentral::Ptax < Autonomia::FerramentasProntas::Provedor
  NOME = 'ptax'.freeze
  HOST = 'olinda.bcb.gov.br'.freeze
  DIAS = 10

  def consultar(_consulta, _params)
    hoje = Time.zone.today
    item = objeto!(exigir!(lista!(objeto!(get(caminho(hoje - DIAS, hoje)))['value'])).last)
    numero = ->(campo) { exigir!(Autonomia::FerramentasProntas::Fontes::BancoCentral.numero(item[campo])) }
    Autonomia::FerramentasProntas::Fontes::BancoCentral.dolar(
      compra: numero.call('cotacaoCompra'), venda: numero.call('cotacaoVenda'),
      data: exigir!(texto(item['dataHoraCotacao']))&.first(10)
    )
  end

  private

  def caminho(inicio, fim)
    '/olinda/servico/PTAX/versao/v1/odata/CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)' \
      "?@dataInicial=%27#{inicio.strftime('%m-%d-%Y')}%27&@dataFinalCotacao=%27#{fim.strftime('%m-%d-%Y')}%27&%24format=json"
  end
end
