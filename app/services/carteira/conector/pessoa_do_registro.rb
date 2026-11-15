# De quem é o seguro de um registro do conector (E7, #2900), nesta ordem:
# 1. o seguro que já está na carteira com a mesma referência (`origem_ref`) diz a pessoa e a empresa: a busca de todo dia
#    e o endosso nunca mudam o dono de um seguro;
# 2. o seguro que já está na carteira com a mesma seguradora e o mesmo número, do mesmo termo, pela MESMA regra do
#    gravador (Carteira::Termo.achar, a de Carteira::Guardar#achar). É o seguro que veio antes pela planilha ou à mão, cuja
#    pessoa pode não ter o documento guardado: ela é a dona, e o CPF/CNPJ do registro fica guardado nela (`de`), se ela
#    ainda não tem um desse tipo. Sem isso, o mesmo seguro nasceria de novo numa pessoa nova (ou seria recusado);
# 3. o CPF/CNPJ do segurado (só dígitos, conferido) é procurado na tabela de documentos da conta (decisão R1, como nos
#    PDFs: Carteira::Trazer::Pdfs::PessoaDoItem). O CNPJ de uma empresa da conta (Enterprise) é a empresa segurada;
# 4. documento que ninguém tem, com o nome do segurado: a pessoa nasce agora (sem telefone, que a plataforma não tem; o
#    e-mail só se ainda não é de outra pessoa da conta), e o documento fica guardado nela.
# NUNCA pelo nome: sem seguro guardado e sem documento, não há como saber quem é, e o registro não entra.
#
# `de` devolve um Dono(pessoa:, empresa:, nova:, ja_na_carteira:) ou nil. `ja_na_carteira`: o registro é um seguro que já
# está na carteira (o mesmo termo), que a gravação atualiza. `achar` é o mesmo sem criar ninguém e sem guardar documento:
# é o que o Conferir usa para contar. Nada daqui vai para log.
class Carteira::Conector::PessoaDoRegistro
  Dono = Struct.new(:pessoa, :empresa, :nova, :ja_na_carteira, keyword_init: true)

  def initialize(account)
    @account = account
    @do_pdf = Carteira::Trazer::Pdfs::PessoaDoItem.new(account)
    @documentos = Relacionamentos::Documentos.new(account)
  end

  def de(lido)
    dono = achar(lido)
    return nova(lido) unless dono

    guardar_o_documento(dono, lido) if dono.ja_na_carteira
    dono
  end

  # O dono que já existe, ou nil.
  def achar(lido)
    dados = dados_do(lido)
    guardada = pela_referencia(lido.valor('ref'))
    return dono_do(guardada, dados && mesmo_termo?(guardada, dados)) if guardada

    guardada = dados && pelo_numero(dados)
    return dono_do(guardada, true) if guardada

    pelo_documento(lido)
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

  def dono_do(apolice, ja_na_carteira)
    Dono.new(pessoa: apolice.contact, empresa: apolice.company, nova: false, ja_na_carteira: ja_na_carteira)
  end

  def pelo_documento(lido)
    return unless documento?(lido)

    pessoa = @do_pdf.achar(lido)
    Dono.new(pessoa: pessoa, empresa: @do_pdf.empresa(lido), nova: false, ja_na_carteira: false) if pessoa
  end

  def nova(lido)
    return unless nasce?(lido)

    Dono.new(pessoa: @do_pdf.criar!(lido), empresa: @do_pdf.empresa(lido), nova: true, ja_na_carteira: false)
  end

  def pela_referencia(ref)
    return if ref.blank?

    Carteira::Apolice.where(account_id: @account.id, origem_ref: ref).includes(:contact, :company).order(:id).first
  end

  def pelo_numero(dados)
    achada = Carteira::Termo.achar(@account.id, dados)
    achada unless achada == Carteira::Termo::AMBIGUO
  end

  def mesmo_termo?(apolice, dados)
    Carteira::Termo.escolher([apolice], dados) == apolice
  end

  # Os dados do registro na forma do banco, como o gravador os compara; nil se algum veio fora dela.
  def dados_do(lido)
    Carteira::Guardar::Dados.call(lido.dados_da_apolice)
  rescue ArgumentError
    nil
  end

  # O CPF fica na pessoa; o CNPJ, na empresa segurada (quando há) ou na pessoa. Só se ela ainda não tem um desse tipo.
  def guardar_o_documento(dono, lido)
    return unless documento?(lido)

    numero = Relacionamentos::NumeroDeDocumento.new(lido.certo('segurado_documento'))
    alvo = !numero.cpf? && dono.empresa ? dono.empresa : dono.pessoa
    @documentos.guardar(alvo, lido.certo('segurado_documento')) unless @documentos.ler(alvo, tipo: numero.tipo)
  rescue CustomExceptions::DocumentoRecusa
    nil
  end
end
