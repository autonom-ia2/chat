# A COMPRA do Seguro Viagem (#3211): monta o corpo do `POST /v1/Compras` da Universal e o link de pagamento. Não chama
# nada e não grava nada.
#
# PREÇO E PLANO SÓ DA COTAÇÃO GUARDADA (R3). `ValorCompra`, `ValorProduto`, `CodigoProduto`, `CodigoTarifaAcordo` e
# `Cambio` saem do plano guardado; datas, destinos e tarifa saem do `pedido` guardado (R4). Do modelo vêm só os dados
# das pessoas, já conferidos por `Viajantes`. O endereço sai do CEP, do lado do servidor (`EnderecoDoCep`); o CEP de
# cidade com CEP único não tem logradouro nem bairro, e a compra vai com eles nulos (R17).
#
# DADO PESSOAL: o corpo leva CPF, nome, e-mail, telefone e endereço. Vai só à Universal; nunca a log nem a banco.
module Autonomia::Agents::Tools::Native::SeguroViagem::Compra
  Faixas = Autonomia::Agents::Tools::Native::SeguroViagem::Faixas

  # 7 é o "Link" do portal da Universal: abre o checkout, onde o cliente escolhe cartão de crédito (com parcelas) ou Pix.
  # A 8 gera um Pix na hora, sem escolha (#3244, compra real de 26/11).
  FORMA_DE_PAGAMENTO_LINK = 7
  TIPO_VIAGEM_UNICA = 1
  TIPO_DOCUMENTO_CPF = 1
  CODIGO_DO_TITULAR = 1
  SEM_MULTIVIAGEM = 0
  PAIS_DO_ENDERECO = 'BR'.freeze
  HOST_DO_PAGAMENTO = 'pagamento.universal-assistance.com'.freeze

  module_function

  # -> Hash do corpo da compra. `viajantes` é a lista de `Viajantes.conferir` (titular primeiro); `contato`, a de
  # `Viajantes.contato`.
  def montar(cotacao:, plano:, viajantes:, endereco:, contato:)
    titular, *demais = viajantes
    saida = Date.iso8601(cotacao.pedido['data_saida'])
    {
      'DadosBasicos' => basicos(cotacao, plano, contato),
      'DadosTitular' => dados_do_titular(titular, endereco, saida),
      'DadosIntegrantes' => demais.each_with_index.map { |dados, indice| pessoa(dados, CODIGO_DO_TITULAR + 1 + indice, saida) },
      'DadosProdutos' => produtos(plano),
      'DadosBeneficios' => [], 'DadosBeneficiosCustomizavel' => [], 'DadosProdutosAvulsos' => [],
      'DadosPagamento' => { 'NomeTitularCartao' => titular['nome_completo'], 'CPFTitular' => titular['cpf'] }
    }
  end

  # O preço guardado do plano (`'360.0'`) em BigDecimal; nil quando falta, não é número, não é finito (NaN, Infinity)
  # ou não passa de zero. A ferramenta recusa o plano sem preço antes de montar a compra.
  def preco(plano)
    valor = BigDecimal(plano['preco_total'].to_s, exception: false)
    valor if valor&.finite? && valor.positive?
  end

  # O link de pagamento é o `urlVoucher` que a compra devolve, com o número do carrinho cifrado. Montar o link com o
  # `codigoCarrinho` cru abre "Carrinho não encontrado" (#3244). Só vale `https` no host de pagamento da Universal, na
  # porta padrão, sem usuário no endereço e com o carrinho na query; qualquer outra coisa: nil.
  def link(url_voucher)
    uri = URI.parse(url_voucher.to_s.strip)
    uri.to_s if pagamento?(uri) && uri.query.present?
  rescue URI::InvalidURIError
    nil
  end

  def pagamento?(uri)
    uri.is_a?(URI::HTTPS) && uri.host == HOST_DO_PAGAMENTO && uri.port == URI::HTTPS::DEFAULT_PORT && uri.userinfo.nil?
  end

  def basicos(cotacao, plano, contato)
    pedido = cotacao.pedido
    {
      'Destinos' => pedido['destinos'], 'TipoViagem' => TIPO_VIAGEM_UNICA,
      'TipoTarifa' => pedido.dig('universal', 'tipoTarifa'),
      'DataSaida' => pedido['data_saida'], 'DataRetorno' => pedido['data_retorno'],
      'ValorCompra' => preco(plano).to_f, 'FormaPagamento' => FORMA_DE_PAGAMENTO_LINK,
      'NomeContatoBrasil' => contato['nome'], 'TelefoneContatoBrasil' => contato['telefone'],
      'CelularContatoBrasil' => contato['telefone']
    }
  end

  def dados_do_titular(titular, endereco, saida)
    pessoa(titular, CODIGO_DO_TITULAR, saida).merge(
      'Telefone' => titular['telefone'], 'Celular' => titular['telefone'], 'Email' => titular['email'],
      'Endereco' => endereco['logradouro'], 'CEP' => titular['cep'], 'Numero' => titular['numero'],
      'Cidade' => endereco['cidade'], 'Bairro' => endereco['bairro'], 'UF' => endereco['uf'],
      'SiglaPaisEndereco' => PAIS_DO_ENDERECO, 'Complemento' => titular['complemento']
    )
  end

  # O que titular e integrante têm em comum: nome e sobrenome (o primeiro nome e o resto), CPF, nascimento e a idade
  # na data da saída.
  def pessoa(dados, codigo, saida)
    nome, sobrenome = dados['nome_completo'].split(' ', 2)
    { 'Codigo' => codigo, 'Nome' => nome, 'Sobrenome' => sobrenome, 'TipoDocumento' => TIPO_DOCUMENTO_CPF,
      'Documento' => dados['cpf'], 'DataNascimento' => dados['nascimento'].iso8601,
      'Idade' => Faixas.idade_em(dados['nascimento'], saida) }
  end

  def produtos(plano)
    { 'CodigoProduto' => plano['id_produto'], 'ValorProduto' => preco(plano).to_f,
      'CodigoPeriodoMultiViagem' => SEM_MULTIVIAGEM, 'CodigoTarifaAcordo' => plano['id_produto_acordo'],
      'Cambio' => plano['cambio'] }
  end

  private_class_method :pagamento?, :basicos, :dados_do_titular, :pessoa, :produtos
end
