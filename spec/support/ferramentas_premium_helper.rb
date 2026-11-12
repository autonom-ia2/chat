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

  # Os arquivos dos 7 cards (`Fontes::Premium::*`), na ordem do catálogo. Cada um guarda em `CONSULTAS` todas as consultas,
  # as desligadas na BigDataCorp também (`Premium::DESLIGADAS_NA_FONTE`, #2946); a `FONTE` leva só as ligadas.
  CARDS_PREMIUM = %w[Certidoes RaioX Pessoa Placa RiscoEndereco ImovelRural ContatoEmpresa].freeze

  def modulos_premium
    CARDS_PREMIUM.map { |nome| "Autonomia::FerramentasProntas::Fontes::Premium::#{nome}".constantize }
  end

  # Todas as consultas do card, as desligadas também.
  def consultas_do_card(chave)
    modulos_premium.find { |modulo| modulo::FONTE.chave == chave }::CONSULTAS
  end

  def todas_as_consultas_premium
    modulos_premium.flat_map { |modulo| modulo::CONSULTAS }
  end

  # O card com TODAS as consultas, como ficará quando a BigDataCorp religar as desligadas: o catálogo devolve este no
  # lugar do real. Prova que a consulta desligada continua certa e volta tirando só a linha dela da lista.
  def card_com_as_desligadas!(chave)
    real = Autonomia::FerramentasProntas::Catalogo.buscar(chave)
    completo = Autonomia::FerramentasProntas::Fonte.new(chave: real.chave, slug: real.slug, nome: real.nome, descricao: real.descricao,
                                                        consultas: consultas_do_card(chave), limite_diario: nil, flag: real.flag,
                                                        termos: real.termos)
    allow(Autonomia::FerramentasProntas::Catalogo).to receive(:buscar).and_call_original
    allow(Autonomia::FerramentasProntas::Catalogo).to receive(:buscar).with(chave).and_return(completo)
    completo
  end

  def com_credencial_da_bigdatacorp(&)
    with_modified_env(BIGDATACORP_USER: USUARIO_FALSO, BIGDATACORP_PASSWORD: SENHA_FALSA, &)
  end

  # O saldo das grátis do card no mês corrente da conta (decisão do Rodrigo, 11/11: as 20 renovam todo mês).
  def saldo_premium!(conta, fonte, contadas, mes: Autonomia::FerramentasProntas::Premium.mes_da_conta(conta))
    Autonomia::FerramentasProntas::Premium::Saldo.create!(account: conta, fonte: fonte, mes: mes, contadas: contadas)
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
  # O token da BigDataCorp vale para o processo inteiro (`Premium::BigDataCorp`): cada exemplo começa sem ele.
  config.before { Autonomia::FerramentasProntas::Premium::BigDataCorp.esquecer_token! }
end
