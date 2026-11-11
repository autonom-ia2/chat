# OS PARÂMETROS DOS CARDS PREMIUM (#2858, F7). Todos normalizados antes de qualquer gasto: o que não normaliza é pedido
# inválido, e a BigDataCorp não é chamada. O CPF e o CNPJ com dígito verificador errado caem aqui e NÃO contam como
# consulta do cliente (decisão do Rodrigo, 11/11: "A, não conta"); o documento que só a BigDataCorp recusa conta
# (`Premium::Leitura::DOCUMENTO_INVALIDO`). É aqui que a recusa acontece por desenho: o card de contato só aceita CNPJ
# (um CPF não passa no dígito do CNPJ), e nenhum card tem parâmetro de telefone, e-mail, endereço ou parente de pessoa.
# Sem regex: método de string e a regra de cada documento.
#
# Regra "QI 70" do Rodrigo (11/11/2026), pela interface `deduza:`/`pergunte:` do `Parametro`:
#   - pergunte (muda o resultado e não dá para deduzir): CNPJ, CPF, PLACA, CODIGO_CAR e NUMERO do imóvel;
#   - deduza (dá para tirar do que o cliente disse): CEP (pela cidade ou pelo endereço, `Premium::Endereco`) e UF (pela
#     cidade, opcional: a mesma das grátis, `Municipios.parametro_uf`). CIDADE, RUA e BAIRRO só existem para achar o CEP;
#     o BAIRRO só se pergunta quando a rua tem mais de um CEP.
# Os textos ficam em `ORIENTACOES` (o `pergunte:` completa "pergunte ao cliente ..."; o `deduza:` é a frase de como
# deduzir), e cada parâmetro recebe a sua: `Parametro.new(..., **ORIENTACOES['cnpj'])`.
module Autonomia::FerramentasProntas::Premium::Parametros
  Parametro = Autonomia::FerramentasProntas::Parametro
  LETRAS = 'A-Z'.freeze
  DIGITOS = '0-9'.freeze
  TAMANHO_DA_PLACA = 7
  # O código do imóvel no CAR: a sigla do estado, o código do município no IBGE (7 dígitos) e 32 letras ou dígitos.
  TAMANHO_DO_CAR = 41
  MAX_NUMERO = 10

  ORIENTACOES = {
    'cnpj' => { pergunte: 'o CNPJ completo da empresa, com as 14 posições' },
    'cpf' => { pergunte: 'o CPF completo da pessoa, com os 11 dígitos' },
    'placa' => { pergunte: 'a placa do veículo, antiga ou Mercosul' },
    'numero' => { pergunte: 'o número do imóvel no endereço (só o número)' },
    'codigo_car' => { pergunte: 'o código do imóvel no CAR, que está no recibo do CAR' },
    'cep' => { deduza: 'no risco do endereço, mande a cidade (criminalidade) ou a rua, o número e a cidade (área de risco e ' \
                       'vistoria), e o CEP sai daí; em empresas na região, mande a rua e a cidade (o CEP geral da cidade ' \
                       'não serve).' },
    'uf' => { deduza: Autonomia::FerramentasProntas::Municipios::DEDUZA_UF },
    'cidade' => { pergunte: 'a cidade do endereço' },
    'rua' => { pergunte: 'a rua do endereço' },
    'bairro' => { pergunte: 'o bairro: a rua tem mais de um CEP na cidade, em bairros diferentes' }
  }.freeze

  # QI 70: pergunte.
  CNPJ = Parametro.new(
    nome: 'cnpj', descricao: 'O CNPJ da empresa como o cliente escreveu (14 posições, com ou sem pontuação).', **ORIENTACOES['cnpj']
  ) { |valor| Parametro.cnpj(valor) }

  # QI 70: pergunte.
  CPF = Parametro.new(
    nome: 'cpf', descricao: 'O CPF da pessoa como o cliente escreveu (11 dígitos, com ou sem pontos e traço).', **ORIENTACOES['cpf']
  ) do |valor|
    cpf = Parametro.digitos(valor, 11)
    cpf if cpf && Autonomia::FerramentasProntas::Fontes::Cpf.valido?(cpf)
  end

  # QI 70: pergunte.
  PLACA = Parametro.new(
    nome: 'placa', descricao: 'A placa do veículo como o cliente escreveu (antiga ou Mercosul, com ou sem traço).', **ORIENTACOES['placa']
  ) { |valor| Autonomia::FerramentasProntas::Premium::Parametros.placa(valor) }

  # QI 70: deduza (no risco do endereço, pela cidade ou pelo endereço; no contato da empresa, a região é a do CEP).
  CEP = Parametro.new(
    nome: 'cep', descricao: 'O CEP do endereço como o cliente escreveu (8 dígitos, com ou sem traço).', **ORIENTACOES['cep']
  ) { |valor| Parametro.digitos(valor, 8) }

  # QI 70: pergunte.
  NUMERO = Parametro.new(
    nome: 'numero', descricao: 'O número do imóvel no endereço (só o número, sem complemento).', **ORIENTACOES['numero']
  ) { |valor| Autonomia::FerramentasProntas::Premium::Parametros.numero(valor) }

  # QI 70: pergunte (está no recibo do CAR).
  CODIGO_CAR = Parametro.new(
    nome: 'codigo_car', descricao: 'O código do imóvel rural no CAR, como está no recibo do cadastro (começa com a sigla do estado).',
    **ORIENTACOES['codigo_car']
  ) { |valor| Autonomia::FerramentasProntas::Premium::Parametros.codigo_car(valor) }

  # Só para achar o CEP (`Premium::Endereco`): locais, não vão à BigDataCorp nem à chave do cache.
  CIDADE = Parametro.new(nome: 'cidade', local: true, descricao: 'A cidade do endereço, quando o cliente não sabe o CEP.',
                         **ORIENTACOES['cidade']) do |valor|
    Parametro.texto_curto(valor)
  end
  # QI 70: deduza (a UF pela cidade). Opcional e a mesma das grátis: aceita a sigla ou o nome do estado, e sai da cidade
  # quando o nome é único no Brasil (`Municipios.falta` recusa a homônima sem UF, com as candidatas).
  UF = Autonomia::FerramentasProntas::Municipios.parametro_uf(local: true)
  RUA = Parametro.new(nome: 'rua', local: true, descricao: 'A rua do endereço, quando o cliente não sabe o CEP.', **ORIENTACOES['rua']) do |valor|
    Parametro.texto_curto(valor)
  end
  # QI 70: pergunte só quando a rua tem mais de um CEP na cidade.
  BAIRRO = Parametro.new(nome: 'bairro', local: true, descricao: 'O bairro, quando a rua tem mais de um CEP na cidade.',
                         **ORIENTACOES['bairro']) do |valor|
    Parametro.texto_curto(valor)
  end
  PELO_ENDERECO = [CEP, RUA, BAIRRO, CIDADE, UF].freeze

  module_function

  # "ABC-1D23" ou "abc1234" -> "ABC1D23" / "ABC1234": 3 letras, 1 dígito, letra ou dígito, 2 dígitos.
  def placa(valor)
    texto = valor.to_s.upcase.delete("^#{LETRAS}#{DIGITOS}")
    return nil unless texto.length == TAMANHO_DA_PLACA
    return nil unless texto[0, 3].delete(LETRAS).empty? && texto[3].delete(DIGITOS).empty? && texto[5, 2].delete(DIGITOS).empty?

    texto
  end

  # Só os dígitos do número do imóvel; "s/n" e vazio não servem.
  def numero(valor)
    texto = valor.to_s.strip
    texto if texto.present? && texto.length <= MAX_NUMERO && texto.delete(DIGITOS).empty?
  end

  # "MT-5107065-A512...": sem pontuação, maiúsculo, com um estado do Brasil e o município em dígitos.
  def codigo_car(valor)
    texto = valor.to_s.upcase.delete("^#{LETRAS}#{DIGITOS}")
    return nil unless texto.length == TAMANHO_DO_CAR && Autonomia::FerramentasProntas::Ufs::SIGLAS.include?(texto[0, 2])
    return nil unless texto[2, 7].delete(DIGITOS).empty?

    texto
  end
end
