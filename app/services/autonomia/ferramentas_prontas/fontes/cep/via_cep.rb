# O CEP no ViaCEP (reserva). CEP que não existe: 200 com `{"erro": true}` (ou "true").
class Autonomia::FerramentasProntas::Fontes::Cep::ViaCep < Autonomia::FerramentasProntas::Provedor
  NOME = 'viacep'.freeze
  HOST = 'viacep.com.br'.freeze

  def consultar(_consulta, params)
    dado = objeto!(get("/ws/#{params['cep']}/json/"))
    raise NaoEncontrado if dado.key?('erro')

    Autonomia::FerramentasProntas::Fontes::Cep.enxuto(
      cep: params['cep'], logradouro: texto(dado['logradouro']), bairro: texto(dado['bairro']),
      cidade: exigir!(texto(dado['localidade'])), uf: exigir!(texto(dado['uf']))
    )
  end
end
