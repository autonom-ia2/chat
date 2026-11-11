# O CEP na BrasilAPI: a ÚLTIMA reserva do endereço pelo CEP (#2906). CEP que não existe: 404, que o cliente HTTP lê como
# `NaoEncontrado`.
#
# Por que por último, e só sem resposta (`SO_SEM_RESPOSTA`): medido em 11/11/2026, a BrasilAPI (v1 e v2) responde todo
# CEP pelo `service: "open-cep"`, um espelho do ViaCEP com linhas de faixa que INVENTA endereço para o CEP que não existe
# (99999-999 vira "Avenida das Torres, Sarandi-PR", quando o ViaCEP diz `{"erro":"true"}`). Por isso ela só responde
# quando nenhuma fonte anterior (ViaCEP, AwesomeAPI) disse "não tem": o CEP inexistente fica "não há registro".
#
# QUANDO ELA RESPONDE: sempre que o ViaCEP e a AwesomeAPI ficam sem resposta, por qualquer falha, e não só quando caem:
# prazo estourado, 5xx, 429 da fonte e o teto do provedor (`TetoDoProvedor`). A fatia de cada conta sem chave é
# ViaCEP 15 por minuto e AwesomeAPI 7 por minuto e 250 por dia; uma conta ativa passa disso no uso normal.
#
# RISCO RESIDUAL, aceito: nesses casos, um CEP que não existe pode receber da BrasilAPI um endereço inventado. Para o CEP
# que existe, o endereço do open-cep confere. Por isso a resposta dela NÃO vai ao cache (`VALIDADE = 0`): o endereço
# inventado não fica 30 dias valendo para todas as contas, e a próxima consulta do mesmo CEP vai de novo ao ViaCEP.
class Autonomia::FerramentasProntas::Fontes::Cep::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze
  SO_SEM_RESPOSTA = true
  VALIDADE = 0

  # Só do CEP para o endereço: a BrasilAPI não busca o CEP pela rua.
  def self.aplica?(consulta, _params)
    consulta.nome == 'endereco'
  end

  def consultar(_consulta, params)
    dado = objeto!(get("/api/cep/v2/#{params['cep']}"))

    Autonomia::FerramentasProntas::Fontes::Cep.enxuto(
      cep: params['cep'], logradouro: texto(dado['street']), bairro: texto(dado['neighborhood']),
      cidade: exigir!(texto(dado['city'])), uf: exigir!(texto(dado['state']))
    )
  end
end
