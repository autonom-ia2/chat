# #2858 (F7): as consultas Premium à BigDataCorp, nos specs. NENHUMA chamada real: o token e cada dataset vêm do
# WebMock, com dados fictícios (CNPJ 11.222.333/0001-81, nomes "EXEMPLO"). A credencial é falsa e só existe no ambiente
# do exemplo (`com_credencial_da_bigdatacorp`).
module FerramentasPremiumHelper
  BDC = 'https://plataforma.bigdatacorp.com.br'.freeze
  USUARIO_FALSO = 'usuario-exemplo-bdc'.freeze
  SENHA_FALSA = 'senha-exemplo-bdc-nao-real'.freeze
  TOKEN_FALSO = 'token-exemplo-bdc-nao-real'.freeze
  CNPJ_EXEMPLO = '11222333000181'.freeze
  CPF_EXEMPLO = '11144477735'.freeze
  CAR_EXEMPLO = "MT5107065#{'EXEMPLO0' * 4}".freeze

  def com_credencial_da_bigdatacorp(&)
    with_modified_env(BIGDATACORP_USER: USUARIO_FALSO, BIGDATACORP_PASSWORD: SENHA_FALSA, &)
  end

  def ligar_premium(conta)
    conta.enable_features!(Autonomia::FerramentasProntas::FLAG, Autonomia::FerramentasProntas::Premium::FLAG)
  end

  def token_da_bigdatacorp
    stub_request(:post, "#{BDC}/tokens/gerar").to_return(status: 200, body: { token: TOKEN_FALSO, tokenID: 'id-exemplo' }.to_json,
                                                         headers: { 'Content-Type' => 'application/json' })
  end

  # O corpo de uma resposta da BigDataCorp para um dataset: `Result[0][resposta] = dado` e o `Status` do dataset.
  def corpo_da_bigdatacorp(dataset, resposta, dado, code: 0, message: 'OK')
    resultado = dado.nil? ? [] : [{ 'MatchKeys' => 'doc{EXEMPLO}', resposta => dado }]
    { 'Result' => resultado, 'QueryId' => "query-exemplo-#{dataset}", 'ElapsedMilliseconds' => 10,
      'Status' => { dataset => [{ 'Code' => code, 'Message' => message }] } }
  end

  # `status_do_dataset`: `code:` e `message:` do `Status` do dataset (padrão 0, "OK").
  def bigdatacorp_responde(rota, dataset, resposta, dado, **status_do_dataset)
    corpo = corpo_da_bigdatacorp(dataset, resposta, dado, **status_do_dataset).to_json
    stub_request(:post, "#{BDC}#{rota}").with(body: hash_including('Datasets' => dataset))
                                        .to_return(status: 200, body: corpo, headers: { 'Content-Type' => 'application/json' })
  end

  # Algum pedido saiu para a BigDataCorp (token ou consulta)? Pelo host, sem expressão regular.
  def chamou_a_bigdatacorp?
    WebMock::RequestRegistry.instance.requested_signatures.hash.keys.any? { |pedido| pedido.uri.host == URI(BDC).host }
  end

  def executar_premium(ferramenta, argumentos)
    JSON.parse(Autonomia::FerramentasProntas.executor_para(ferramenta, params: argumentos).call)
  end

  def registros_premium
    Autonomia::FerramentasProntas::Premium::Registro.order(:id)
  end
end

RSpec.configure do |config|
  config.include FerramentasPremiumHelper
end
