# O CPF e o CNPJ das pessoas e das empresas de uma conta (épico #1240, decisão R1): guardar, achar o dono pelo número
# e ler o de um dono. É a porta única da tabela `relacionamentos_documentos`; tudo aqui vale só dentro da conta.
#
#   documentos = Relacionamentos::Documentos.new(account)
#   documentos.guardar(pessoa, '123.456.789-09')  # => Relacionamentos::Documento
#   documentos.donos('12345678909')               # => [pessoa]
#   documentos.ler(pessoa)&.mascarado             # => '***.***.***-09'
#
# O número chega com ou sem pontuação e é sempre comparado inteiro (valor exato), nunca por pedaço. O tipo sai do
# próprio número: 11 dígitos é CPF, 14 caracteres é CNPJ. O CNPJ com letra só vale escrito com a pontuação completa
# (12.ABC.345/01DE-35). A pessoa pode ter CPF e CNPJ (o MEI é pessoa com CNPJ); a empresa só tem CNPJ.
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
  # Levanta CustomExceptions::DocumentoRecusa com o código 'invalido' (o número não confere), 'cpf_em_empresa' (CPF numa
  # empresa) ou 'letra_fora_da_forma_do_cnpj' (texto com letra que não está na forma XX.XXX.XXX/XXXX-DD, inclusive o
  # CNPJ com letra sem pontuação); dono de outra conta levanta ActiveRecord::RecordInvalid. Nenhum dos erros traz o número.
  #
  # Dois pedidos ao mesmo tempo para o mesmo dono e o mesmo tipo (um job por arquivo, dois arquivos da mesma pessoa): os
  # dois não acham documento, e o índice único recusa o segundo a gravar. Ele tenta de novo uma vez, agora achando o
  # documento que o primeiro criou; se o banco recusar de novo, o erro sobe. Cada tentativa tem transação própria
  # (savepoint), para a recusa do banco não derrubar a transação de quem chamou.
  def guardar(dono, texto)
    numero = Relacionamentos::NumeroDeDocumento.new(texto)
    recusa = motivo_da_recusa(numero, dono)
    raise CustomExceptions::DocumentoRecusa, recusa if recusa

    gravar(dono, numero)
  rescue ActiveRecord::RecordNotUnique
    gravar(dono, numero)
  end

  # As pessoas e as empresas da conta que têm este número, da mais antiga para a mais nova. Pode vir mais de uma: a
  # tabela não impede o mesmo número em dois cadastros, e quem casa pessoa decide. Número que não confere não é de
  # ninguém: devolve vazio. O CNPJ com letra só é achado escrito na forma XX.XXX.XXX/XXXX-DD.
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

  def motivo_da_recusa(numero, dono)
    return 'letra_fora_da_forma_do_cnpj' if numero.letra_fora_da_forma?
    return 'invalido' unless numero.valido?

    'cpf_em_empresa' if numero.cpf? && empresa?(dono)
  end

  def gravar(dono, numero)
    Relacionamentos::Documento.transaction(requires_new: true) do
      do_tipo(dono, numero.tipo).tap { |documento| documento.update!(valor: numero.canonico) }
    end
  end

  def empresa?(dono)
    Relacionamentos::Documento.coluna_do(dono) == :company_id
  end

  def do_tipo(dono, tipo)
    do_dono(dono).find_or_initialize_by(tipo: tipo)
  end

  def da_conta
    Relacionamentos::Documento.da_conta(@account)
  end

  def do_dono(dono)
    da_conta.do_dono(dono)
  end
end
