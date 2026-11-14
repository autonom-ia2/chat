# "Trazer minha lista" com seguros (E4, #2897): de quantas PESSOAS são as linhas que entram. Na planilha com seguros a
# mesma pessoa aparece em várias linhas, e a conta da tela ("164 seguros de 118 pessoas") não pode contar linha.
#
# A mesma pessoa é quem tem o mesmo telefone ou o mesmo e-mail, pelos resumos que cada linha boa guarda
# (`normalized_phone_hash`, `normalized_email_hash`): o critério da leitura (ContactImports::Trazer::MesmaPessoa). Duas
# linhas boas da mesma pessoa nunca têm telefones nem e-mails diferentes (isso é a linha repetida, que não entra), então
# as pessoas são os telefones distintos mais os e-mails que não aparecem em nenhuma linha com telefone. Sai em duas
# consultas, sem carregar as linhas.
#
# As linhas que a pessoa consertou na tela ainda são problema no banco e não guardam resumo: entram na conta pelo que
# o conserto guardou (ContactImports::Trazer::QuemEntra#novas), só quando são de alguém que as linhas boas não têm.
#
# Depois de gravada a lista, a conta é outra e mais simples: os contatos distintos das linhas gravadas (`gravadas`).
class Carteira::Trazer::PessoasQueEntram
  def initialize(importacao, quem_entra)
    @importacao = importacao
    @quem_entra = quem_entra
  end

  def quantas
    por_telefone = com_telefone.distinct.count(:normalized_phone_hash)
    por_telefone + so_com_email.distinct.count(:normalized_email_hash) + consertadas
  end

  # { seguros:, pessoas:, pessoasNovas:, pessoasQueJaEstavam: } das linhas já gravadas de uma lista trazida. A pessoa é
  # nova quando alguma linha dela criou o contato; as linhas seguintes da mesma pessoa já a encontram na conta.
  def self.gravadas(importacao)
    linhas = importacao.campaign_import_rows.status_imported
    pessoas = linhas.distinct.count(:contact_id)
    novas = linhas.where(was_existing_contact: false).distinct.count(:contact_id)
    { seguros: linhas.count, pessoas: pessoas, pessoasNovas: novas, pessoasQueJaEstavam: pessoas - novas }
  end

  private

  def boas
    @importacao.campaign_import_rows.status_valid.where.not(row_number: @quem_entra.trocadas)
  end

  def com_telefone
    boas.where.not(normalized_phone_hash: nil)
  end

  def so_com_email
    boas.where(normalized_phone_hash: nil).where.not(normalized_email_hash: nil)
        .where.not(normalized_email_hash: com_telefone.where.not(normalized_email_hash: nil).select(:normalized_email_hash))
  end

  # As linhas consertadas que são de uma pessoa que nenhuma linha boa tem, sem contar a mesma pessoa duas vezes.
  def consertadas
    marcas = marcas_das_consertadas
    return 0 if marcas.empty?

    ja_contadas = das_boas(:normalized_phone_hash, marcas.filter_map(&:first)) + das_boas(:normalized_email_hash, marcas.filter_map(&:last))
    marcas.reject { |marca| marca.intersect?(ja_contadas) }.uniq { |telefone, email| telefone || email }.size
  end

  # [[resumo do telefone, resumo do e-mail], ...] das linhas consertadas que vão entrar.
  def marcas_das_consertadas
    @quem_entra.novas.values.map { |conferida| conferida.values_at('phone_hash', 'email_hash').map(&:presence) }
  end

  # Os resumos (de telefone ou de e-mail) que alguma linha boa também tem.
  def das_boas(coluna, resumos)
    boas.where(coluna => resumos).distinct.pluck(coluna)
  end
end
