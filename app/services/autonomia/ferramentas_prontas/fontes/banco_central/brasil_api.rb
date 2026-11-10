# As taxas na BrasilAPI (reserva da Selic e do IPCA). Do IPCA ela só tem o acumulado de 12 meses.
class Autonomia::FerramentasProntas::Fontes::BancoCentral::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze
  SIGLAS = { 'selic' => 'selic', 'ipca' => 'ipca' }.freeze

  def consultar(consulta, _params)
    dado = objeto!(get("/api/taxas/v1/#{SIGLAS.fetch(consulta.nome)}"))
    valor = exigir!(Autonomia::FerramentasProntas::Fontes::BancoCentral.numero(dado['valor']))
    banco = Autonomia::FerramentasProntas::Fontes::BancoCentral
    consulta.nome == 'selic' ? banco.selic(valor) : banco.ipca(mes: nil, no_mes: nil, em_12_meses: valor)
  end
end
