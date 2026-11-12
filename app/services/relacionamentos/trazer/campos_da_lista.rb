# "Trazer minha lista" (#2896): os campos que uma lista preencheu e que ainda não foram devolvidos, em blocos, cada um
# já diante da pessoa (ou da empresa) de hoje (Relacionamentos::Trazer::CampoQueVolta). A prévia conta por aqui e o
# Desfazer devolve por aqui, então o que a prévia promete é o que o Desfazer faz.
#
# Ficam de fora os campos de uma pessoa que a própria lista criou (a mesma pessoa em duas linhas: a primeira a cria e a
# segunda a completa). Essa pessoa sai inteira ou fica inteira (Relacionamentos::Trazer::QuemFica); nada dela "volta".
# O telefone da empresa entra sempre: ele fica na empresa da linha, que pode ser de outras pessoas.
#
# Cada bloco custa um número fixo de consultas: as linhas (para achar a empresa), as pessoas, as empresas e quem tem
# card ganho desde a lista.
class Relacionamentos::Trazer::CamposDaLista
  Campo = Relacionamentos::CampoPreenchido
  BLOCO = Relacionamentos::Trazer::QuemFica::BLOCO

  def initialize(importacao)
    @importacao = importacao
    @conta = importacao.account
  end

  # Entrega, bloco a bloco, um CampoQueVolta por campo ainda não devolvido.
  def em_blocos
    pendentes.in_batches(of: BLOCO) { |bloco| yield montar(bloco.to_a) }
  end

  private

  def pendentes
    criadas = Relacionamentos::Trazer::QuemFica.new(@importacao).criadas.select(:contact_id)
    da_lista = Campo.pendentes.da_importacao(@importacao)
    da_lista.where(campo: Campo::TELEFONE_DA_EMPRESA).or(da_lista.where.not(contact_id: criadas))
  end

  def montar(registros)
    da_empresa, da_pessoa = registros.partition(&:da_empresa?)
    das_pessoas(da_pessoa) + das_empresas(da_empresa)
  end

  def das_pessoas(registros)
    pessoas = @conta.contacts.where(id: registros.map(&:contact_id).uniq).index_by(&:id)
    ganharam = quem_ganhou(registros.select { |registro| registro.campo == Campo::CLIENTE }.map(&:contact_id))
    registros.map do |registro|
      campo(registro, pessoas[registro.contact_id], ganhou: ganharam.include?(registro.contact_id))
    end
  end

  # Sem telefone de empresa no bloco, nada é consultado (e Empresas pode nem existir na instalação).
  def das_empresas(registros)
    return [] if registros.empty?

    linhas = @importacao.campaign_import_rows.where(id: registros.map(&:campaign_import_row_id)).where.not(company_id: nil)
    empresa_da_linha = linhas.pluck(:id, :company_id).to_h
    empresas = @conta.companies.where(id: empresa_da_linha.values.uniq).index_by(&:id)
    registros.map { |registro| campo(registro, empresas[empresa_da_linha[registro.campaign_import_row_id]]) }
  end

  def campo(registro, alvo, ganhou: false)
    Relacionamentos::Trazer::CampoQueVolta.new(registro, alvo: alvo, desde: @importacao.created_at, ganhou: ganhou)
  end

  def quem_ganhou(pessoas)
    return Set.new if pessoas.empty?

    Crm::Card.won.where(account_id: @conta.id, contact_id: pessoas, closed_at: @importacao.created_at..).distinct.pluck(:contact_id).to_set
  end
end
