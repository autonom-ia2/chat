# O telefone e o e-mail do segurado lidos de uma apólice (E6, #2899). Uma apólice traz vários telefones: o da
# seguradora, o da assistência, o do corretor. Gravar um deles na ficha do cliente é pior que não gravar nenhum, então
# o contato só sai daqui quando passa nas conferências de valor abaixo, depois de o modelo dizer que ele é do segurado:
# 1. o leitor achou o CPF/CNPJ do segurado (sem ele não há "página do segurado");
# 2. a página em que o modelo diz que o contato está é uma página em que esse CPF/CNPJ está escrito, inteiro;
# 3. o contato está escrito nessa página por inteiro (Carteira::Leitor::Tokens): o telefone, em blocos de número
#    seguidos, sem nada no meio ("(11) 99999-0001"); o e-mail, como um bloco só, emendando só a quebra de linha. Um
#    pedaço de outro número ou de outro e-mail não passa;
# 4. o telefone é fixo ou celular do Brasil com DDD que existe (a biblioteca de telefone da casa). Ficam de fora o
#    0800, os números de central (4004, 3003), o telefone sem DDD ou com DDD que não existe, e o "telefone" que é o
#    próprio CPF/CNPJ ou o número da apólice.
# Falhou qualquer uma: "não achei" (nil). Não há lista de palavras nem regex: quem decide de quem é o telefone é o
# modelo; aqui só se confere o que está escrito e onde.
#
# AINDA ASSIM O CONTATO NÃO É DADO POR CERTO. O telefone do corretor costuma estar na mesma página do CPF do segurado,
# e nenhuma conferência de valor separa um do outro. Por isso o resultado marca os dois como "a confirmar"
# (Carteira::Leitor::Resultado#a_confirmar): quem recebe mostra para a pessoa confirmar antes de gravar.
#
# O telefone sai só com os dígitos, como está escrito na apólice (com o DDD, sem código do país acrescentado); pôr no
# formato da ficha é de quem grava a pessoa. O e-mail sai em minúsculas.
class Carteira::Leitor::ContatoDoSegurado
  PAIS = :br
  TIPOS_DE_TELEFONE = %i[mobile fixed_line].freeze
  GRATUITO = '0800'.freeze
  MAXIMO_DO_EMAIL = 254
  ARROBA = '@'.freeze
  PONTO = '.'.freeze
  TOKENS = Carteira::Leitor::Tokens

  # paginas: as que foram ao modelo. documento: os dígitos do CPF/CNPJ do segurado já conferidos, ou nil. numero: o
  # número da apólice já conferido, ou nil.
  def initialize(paginas, documento:, numero: nil)
    @documento = documento.to_s
    @da_apolice = TOKENS.digitos(numero)
    @do_segurado = @documento.empty? ? [] : paginas.select { |pagina| pagina.tokens.numeros.include?(@documento) }
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

    numero = TOKENS.digitos(valor)
    numero if de_pessoa?(numero) && pagina.tokens.numeros_seguidos?(numero)
  end

  def de_pessoa?(numero)
    return false if numero.start_with?(GRATUITO) || [@documento, @da_apolice].include?(numero)

    TelephoneNumber.valid?(numero, PAIS, TIPOS_DE_TELEFONE)
  end

  def email(valor, numero_da_pagina)
    pagina = pagina_do_segurado(numero_da_pagina)
    return unless pagina && valor.is_a?(String)

    endereco = valor.strip.downcase
    endereco if com_cara_de_email?(endereco) && escrito_inteiro?(pagina.tokens, endereco)
  end

  # O endereço é um bloco só, e esse bloco está na página, como está ou com uma quebra de linha no meio.
  def escrito_inteiro?(tokens, endereco)
    bloco = TOKENS.new(endereco).blocos
    bloco.one? && (tokens.blocos.include?(bloco.first) || tokens.blocos_emendados.include?(bloco.first))
  end

  def pagina_do_segurado(numero)
    @do_segurado.find { |pagina| pagina.numero == numero }
  end

  # Uma arroba só, algo antes dela, um ponto no domínio e nenhum espaço. É conferência de forma, não validação de
  # entrega: o endereço já foi achado escrito na página.
  def com_cara_de_email?(endereco)
    usuario, dominio, sobra = endereco.split(ARROBA, 3)
    return false if sobra || usuario.blank? || endereco.length > MAXIMO_DO_EMAIL

    endereco == endereco.split.join && dominio_com_ponto?(dominio.to_s)
  end

  def dominio_com_ponto?(dominio)
    dominio.include?(PONTO) && !dominio.start_with?(PONTO) && !dominio.end_with?(PONTO)
  end
end
