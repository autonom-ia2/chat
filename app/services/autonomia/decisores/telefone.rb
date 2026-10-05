# O telefone que o Decisor tirou do texto, no formato que o contato aceita (+5522974049400).
#
# A pessoa escreve "22974049400", "(22) 97404-9400" ou "+55 22 97404-9400"; o modelo não deve inventar o
# código do país (#1000). Quem completa é o código, com a gem `telephone_number` e o país da conta,
# tirado do idioma dela (pt_BR → Brasil). Sem país e sem "+", o número não é adivinhado.
class Autonomia::Decisores::Telefone
  # O app trata "pt" como apelido de pt_BR (config/initializers/languages.rb).
  PAIS_SEM_SUFIXO = { 'pt' => :br }.freeze

  def initialize(account)
    @account = account
  end

  def normalizar(texto)
    bruto = texto.to_s.strip
    digitos = bruto.delete('^0-9')
    return if digitos.empty?

    internacional = valido("+#{digitos}")
    return internacional if bruto.start_with?('+')

    (pais && valido(digitos, pais)) || internacional
  end

  private

  def valido(numero, codigo = nil)
    analisado = codigo ? TelephoneNumber.parse(numero, codigo) : TelephoneNumber.parse(numero)
    analisado.e164_number if analisado.valid?
  end

  def pais
    idioma = @account&.locale.to_s
    sufixo = idioma.split('_')[1]
    return sufixo.downcase.to_sym if sufixo.present?

    PAIS_SEM_SUFIXO[idioma]
  end
end
