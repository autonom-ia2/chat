# O CPF e o CNPJ das pessoas e das empresas de uma conta (épico #1240, decisão R1): guardar, achar o dono pelo número
# e ler o de um dono. É a porta única da tabela `relacionamentos_documentos`; tudo aqui vale só dentro da conta.
#
#   documentos = Relacionamentos::Documentos.new(account)
#   documentos.guardar(pessoa, '123.456.789-09')  # => Relacionamentos::Documento
#   documentos.donos('12345678909')               # => [pessoa]
#   documentos.ler(pessoa)&.mascarado             # => '***.***.***-09'
#
# O número chega com ou sem pontuação e é sempre comparado inteiro (valor exato), nunca por pedaço. O tipo sai do
# próprio número: 11 dígitos é CPF, 14 caracteres é CNPJ.
#
# O número inteiro não vai para log, erro, cache nem argumento de job. Para isso, e para lista na tela, use
# `mascarado`; `valor` e `formatado` são para quem precisa do número (a ficha, a cotação).
class Relacionamentos::Documentos
  # O documento que se espera de cada dono quando ninguém diz o tipo: o CPF da pessoa, o CNPJ da empresa.
  TIPO_DO_DONO = { contact_id: Relacionamentos::NumeroDeDocumento::CPF, company_id: Relacionamentos::NumeroDeDocumento::CNPJ }.freeze

  def initialize(account)
    @account = account
  end

  # Guarda o CPF ou o CNPJ do dono (uma pessoa ou uma empresa da conta). Se o dono já tem documento desse tipo, troca.
  # Número que não confere levanta CustomExceptions::DocumentoRecusa ('invalido'); dono de outra conta levanta
  # ActiveRecord::RecordInvalid. Nenhum dos dois erros traz o número.
  def guardar(dono, texto)
    numero = Relacionamentos::NumeroDeDocumento.new(texto)
    raise CustomExceptions::DocumentoRecusa, 'invalido' unless numero.valido?

    documento = do_dono(dono).find_or_initialize_by(tipo: numero.tipo)
    documento.update!(valor: numero.canonico)
    documento
  end

  # As pessoas e as empresas da conta que têm este número, da mais antiga para a mais nova. Pode vir mais de uma: a
  # tabela não impede o mesmo número em dois cadastros, e quem casa pessoa decide. Número que não confere não é de
  # ninguém: devolve vazio.
  def donos(texto)
    numero = Relacionamentos::NumeroDeDocumento.new(texto)
    return [] unless numero.valido?

    da_conta.where(tipo: numero.tipo, valor: numero.canonico).includes(:contact, :company).order(:id).map(&:dono)
  end

  # O documento do dono, ou nil. Sem `tipo`, o CPF da pessoa e o CNPJ da empresa.
  def ler(dono, tipo: nil)
    do_dono(dono).find_by(tipo: tipo || TIPO_DO_DONO.fetch(Relacionamentos::Documento.coluna_do(dono)))
  end

  private

  def da_conta
    Relacionamentos::Documento.da_conta(@account)
  end

  def do_dono(dono)
    da_conta.do_dono(dono)
  end
end
