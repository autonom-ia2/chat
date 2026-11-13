# O telefone e o e-mail do segurado lidos de uma apólice (E6, #2899). Uma apólice traz vários telefones: o da
# seguradora, o da assistência, o do corretor. Gravar um deles na ficha do cliente é pior que não gravar nenhum, então
# o contato só é aceito quando passa em TRÊS conferências de valor, depois de o modelo dizer que ele é do segurado:
# 1. o leitor achou o CPF/CNPJ do segurado (sem ele não há "página do segurado");
# 2. a página em que o modelo diz que o contato está é uma página em que os dígitos desse CPF/CNPJ aparecem;
# 3. os dígitos do telefone (ou o e-mail) estão de fato escritos nessa página.
# Falhou qualquer uma: "não achei" (nil). Não há lista de palavras nem regex: quem decide de quem é o telefone é o
# modelo; aqui só se confere onde ele está.
#
# O telefone sai só com os dígitos, como está escrito na apólice (com o DDD, sem código do país acrescentado); pôr no
# formato da ficha é de quem grava a pessoa. O e-mail sai em minúsculas.
class Carteira::Leitor::ContatoDoSegurado
  # DDD + número (10 ou 11 dígitos); com o 55 escrito na frente, 12 ou 13.
  DIGITOS_DO_TELEFONE = (10..13)
  MAXIMO_DO_EMAIL = 254
  ARROBA = '@'.freeze
  PONTO = '.'.freeze

  # paginas: as que foram ao modelo. documento: os dígitos do CPF/CNPJ do segurado já conferidos, ou nil.
  def initialize(paginas, documento:)
    @do_segurado = documento.present? ? paginas.select { |pagina| digitos(pagina.texto).include?(documento) } : []
  end

  # resposta: o JSON do modelo. Devolve { 'segurado_telefone' => dígitos ou nil, 'segurado_email' => e-mail ou nil }.
  def call(resposta)
    { 'segurado_telefone' => telefone(resposta['segurado_telefone'], resposta['segurado_telefone_pagina']),
      'segurado_email' => email(resposta['segurado_email'], resposta['segurado_email_pagina']) }
  end

  private

  def telefone(valor, numero_da_pagina)
    pagina = pagina_do_segurado(numero_da_pagina)
    return unless pagina && valor.is_a?(String)

    numero = digitos(valor)
    numero if DIGITOS_DO_TELEFONE.cover?(numero.length) && digitos(pagina.texto).include?(numero)
  end

  def email(valor, numero_da_pagina)
    pagina = pagina_do_segurado(numero_da_pagina)
    return unless pagina && valor.is_a?(String)

    endereco = valor.strip.downcase
    endereco if com_cara_de_email?(endereco) && sem_espacos(pagina.texto.downcase).include?(endereco)
  end

  def pagina_do_segurado(numero)
    @do_segurado.find { |pagina| pagina.numero == numero }
  end

  # Uma arroba só, algo antes dela, um ponto no domínio e nenhum espaço. É conferência de forma, não validação de
  # entrega: o endereço já foi achado escrito na página.
  def com_cara_de_email?(endereco)
    usuario, dominio, sobra = endereco.split(ARROBA, 3)
    return false if sobra || usuario.blank? || endereco.length > MAXIMO_DO_EMAIL

    endereco == sem_espacos(endereco) && dominio_com_ponto?(dominio.to_s)
  end

  def dominio_com_ponto?(dominio)
    dominio.include?(PONTO) && !dominio.start_with?(PONTO) && !dominio.end_with?(PONTO)
  end

  def sem_espacos(texto)
    texto.split.join
  end

  def digitos(texto)
    Carteira::Leitor::Ancora.digitos(texto)
  end
end
