# De quem é o seguro de um PDF do lote (E6.3, #2899): a pessoa da conta que é o segurado, ou a que nasce para ele.
#
# 1. Pelo documento (decisão R1): o CPF/CNPJ que o leitor achou com certeza é procurado na tabela cifrada
#    (Relacionamentos::Documentos), por valor exato. A mesma pessoa pode estar cadastrada duas vezes com o mesmo número:
#    fica a mais antiga, como a tabela devolve. O CNPJ de uma empresa da conta (Enterprise) é a empresa segurada.
#    Com documento lido, o telefone e o e-mail NUNCA casam ninguém: se o documento não achou a pessoa, ela é nova.
# 2. Sem documento lido, pelo telefone ou pelo e-mail do segurado, SÓ depois de alguém confirmar no Conferir que eles
#    são do cliente (Carteira::ItemLido#certo?). O leitor nunca dá o contato por certo: a apólice traz o telefone do
#    corretor na mesma página do CPF. Contato a confirmar não casa ninguém e não é gravado em ninguém.
# 3. Ninguém: `criar!` faz a pessoa com o nome lido (ou escrito no Conferir), o telefone e o e-mail confirmados, como
#    cliente, e guarda o CPF/CNPJ dela na tabela de documentos. A pessoa que já existia não é alterada.
#
# Nada daqui vai para log: o documento, o nome e o contato só existem no banco.
class Carteira::Trazer::Pdfs::PessoaDoItem
  def initialize(account)
    @account = account
    @documentos = Relacionamentos::Documentos.new(account)
  end

  # A pessoa da conta que é o segurado, ou nil.
  def achar(lido)
    return donos(lido).find { |dono| dono.is_a?(Contact) } if lido.certo('segurado_documento')

    pelo_contato(lido)
  end

  # A empresa da conta dona do CNPJ lido, ou nil.
  def empresa(lido)
    donos(lido).find { |dono| !dono.is_a?(Contact) }
  end

  def criar!(lido)
    pessoa = @account.contacts.create!(name: lido.certo('segurado_nome'), phone_number: telefone_livre(lido), email: email_livre(lido),
                                       contact_type: :customer)
    guardar_documento(pessoa, lido)
    pessoa
  end

  private

  def donos(lido)
    documento = lido.certo('segurado_documento')
    documento ? @documentos.donos(documento) : []
  end

  def pelo_contato(lido)
    por_telefone = Crm::BookingV2::PhoneLookup.find_contact(account: @account, e164: telefone(lido))
    por_telefone || por_email(lido.certo('segurado_email'))
  end

  def por_email(email)
    @account.contacts.where('LOWER(contacts.email) = ?', email.downcase).order(:id).first if email.present?
  end

  # O telefone confirmado, no formato da ficha (E.164), ou nil.
  def telefone(lido)
    numero = lido.certo('segurado_telefone')
    Crm::BookingV2::PhoneLookup.normalize(numero) if numero
  end

  # O telefone e o e-mail que já são de outra pessoa da conta não vão para a que nasce (a ficha não tira o contato de ninguém,
  # e o contato repetido recusaria a pessoa inteira): ela nasce sem eles.
  def telefone_livre(lido)
    numero = telefone(lido)
    numero unless numero && Crm::BookingV2::PhoneLookup.find_contact(account: @account, e164: numero)
  end

  def email_livre(lido)
    email = lido.certo('segurado_email')
    email unless por_email(email)
  end

  # O documento que não confere (o leitor só o acha inteiro, mas o dígito pode não bater) não impede a pessoa de nascer.
  def guardar_documento(pessoa, lido)
    documento = lido.certo('segurado_documento')
    @documentos.guardar(pessoa, documento) if documento
  rescue CustomExceptions::DocumentoRecusa
    nil
  end
end
