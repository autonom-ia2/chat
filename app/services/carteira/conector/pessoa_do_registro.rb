# De quem é o seguro de um registro do conector (E7, #2900):
# 1. o seguro que já está na carteira com a mesma referência (`origem_ref`) diz a pessoa e a empresa: a busca de todo dia
#    e o endosso nunca mudam o dono de um seguro;
# 2. o CPF/CNPJ do segurado (só dígitos, conferido) é procurado na tabela de documentos da conta (decisão R1, como nos
#    PDFs: Carteira::Trazer::Pdfs::PessoaDoItem). O CNPJ de uma empresa da conta (Enterprise) é a empresa segurada;
# 3. documento que ninguém tem, com o nome do segurado: a pessoa nasce agora (sem telefone, que a plataforma não tem; o
#    e-mail só se ainda não é de outra pessoa da conta), e o documento fica guardado nela.
# NUNCA pelo nome: sem documento e sem seguro guardado com a referência, não há como saber quem é, e o registro não entra.
#
# `de` devolve um Dono(pessoa:, empresa:, nova:) ou nil. `achar` é o mesmo sem criar ninguém: é o que o Conferir usa para
# contar. Nada daqui vai para log.
class Carteira::Conector::PessoaDoRegistro
  Dono = Struct.new(:pessoa, :empresa, :nova, keyword_init: true)

  def initialize(account)
    @account = account
    @do_pdf = Carteira::Trazer::Pdfs::PessoaDoItem.new(account)
  end

  def de(lido)
    achar(lido) || nova(lido)
  end

  # O dono que já existe, ou nil.
  def achar(lido)
    guardada = pela_referencia(lido.valor('ref'))
    return Dono.new(pessoa: guardada.contact, empresa: guardada.company, nova: false) if guardada
    return unless documento?(lido)

    pessoa = @do_pdf.achar(lido)
    Dono.new(pessoa: pessoa, empresa: @do_pdf.empresa(lido), nova: false) if pessoa
  end

  # Quem entraria como pessoa nova: documento que confere e o nome do segurado.
  def nasce?(lido)
    documento?(lido) && lido.certo('segurado_nome').present?
  end

  def documento?(lido)
    documento = lido.certo('segurado_documento')
    documento.present? && Relacionamentos::NumeroDeDocumento.new(documento).valido?
  end

  private

  def nova(lido)
    return unless nasce?(lido)

    Dono.new(pessoa: @do_pdf.criar!(lido), empresa: @do_pdf.empresa(lido), nova: true)
  end

  def pela_referencia(ref)
    return if ref.blank?

    Carteira::Apolice.where(account_id: @account.id, origem_ref: ref).includes(:contact, :company).order(:id).first
  end
end
