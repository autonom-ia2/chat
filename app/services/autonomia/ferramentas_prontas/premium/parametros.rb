# OS PARÂMETROS DOS CARDS PREMIUM (#2858, F7). Todos normalizados antes de qualquer gasto: o que não normaliza é pedido
# inválido, e a BigDataCorp não é chamada. É aqui que a recusa acontece por desenho: o card de contato só aceita CNPJ
# (um CPF não passa no dígito do CNPJ), e nenhum card tem parâmetro de telefone, e-mail, endereço ou parente de pessoa.
# Sem regex: método de string e a regra de cada documento.
module Autonomia::FerramentasProntas::Premium::Parametros
  Parametro = Autonomia::FerramentasProntas::Parametro
  LETRAS = 'A-Z'.freeze
  DIGITOS = '0-9'.freeze
  TAMANHO_DA_PLACA = 7
  # O código do imóvel no CAR: a sigla do estado, o código do município no IBGE (7 dígitos) e 32 letras ou dígitos.
  TAMANHO_DO_CAR = 41
  MAX_NUMERO = 10

  CNPJ = Parametro.new(
    nome: 'cnpj', descricao: 'O CNPJ da empresa como o cliente escreveu (14 posições, com ou sem pontuação).'
  ) { |valor| Parametro.cnpj(valor) }

  CPF = Parametro.new(
    nome: 'cpf', descricao: 'O CPF da pessoa como o cliente escreveu (11 dígitos, com ou sem pontos e traço).'
  ) do |valor|
    cpf = Parametro.digitos(valor, 11)
    cpf if cpf && Autonomia::FerramentasProntas::Fontes::Cpf.valido?(cpf)
  end

  PLACA = Parametro.new(
    nome: 'placa', descricao: 'A placa do veículo como o cliente escreveu (antiga ou Mercosul, com ou sem traço).'
  ) { |valor| Autonomia::FerramentasProntas::Premium::Parametros.placa(valor) }

  CEP = Parametro.new(
    nome: 'cep', descricao: 'O CEP do endereço como o cliente escreveu (8 dígitos, com ou sem traço).'
  ) { |valor| Parametro.digitos(valor, 8) }

  NUMERO = Parametro.new(
    nome: 'numero', descricao: 'O número do imóvel no endereço (só o número, sem complemento).'
  ) { |valor| Autonomia::FerramentasProntas::Premium::Parametros.numero(valor) }

  CODIGO_CAR = Parametro.new(
    nome: 'codigo_car', descricao: 'O código do imóvel rural no CAR, como está no recibo do cadastro (começa com a sigla do estado).'
  ) { |valor| Autonomia::FerramentasProntas::Premium::Parametros.codigo_car(valor) }

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
