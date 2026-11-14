# "Trazer minha lista" (#2896): os campos que uma lista preencheu e que ainda não foram devolvidos, em blocos, cada um
# já diante da pessoa (ou da empresa) de hoje (Relacionamentos::Trazer::CampoQueVolta). A prévia conta por aqui e o
# Desfazer devolve por aqui, então o que a prévia promete é o que o Desfazer faz.
#
# Ficam de fora os campos de uma pessoa que a própria lista criou (a mesma pessoa em duas linhas: a primeira a cria e a
# segunda a completa). Essa pessoa sai inteira ou fica inteira (Relacionamentos::Trazer::QuemFica); nada dela "volta".
# O telefone da empresa entra sempre: ele fica na empresa da linha, que pode ser de outras pessoas.
#
# Cada bloco custa um número fixo de consultas: os campos do bloco, as pessoas, quem tem card ganho desde a lista e quem
# já foi procurado desde a lista (Relacionamentos::Trazer::QuemFoiProcurado); com telefone de empresa no bloco, mais as
# linhas (para achar a empresa) e as empresas. A consulta que acha o bloco relê as linhas da lista inteira, então o
# tempo cresce com o número de blocos. Só o Desfazer faz uma consulta a mais por pessoa, e só para a marca de cliente:
# o card ganho é conferido de novo com a pessoa travada (Relacionamentos::Trazer::CampoQueVolta#desmarcar_cliente).
class Relacionamentos::Trazer::CamposDaLista
  Campo = Relacionamentos::CampoPreenchido
  BLOCO = Relacionamentos::Trazer::QuemFica::BLOCO
  # A prévia só conta e roda dentro do pedido da tela, que tem prazo: lê em blocos maiores, para fazer menos consultas.
  # O Desfazer continua no bloco de sempre, que é também o passo em que ele mostra que está vivo.
  BLOCO_DA_PREVIA = 2_000
  # O que a prévia e o Desfazer leem de cada campo. O Desfazer grava `devolvido_em` sem precisar tê-lo lido.
  COLUNAS = %i[id campo contact_id campaign_import_row_id valor_posto_hash tipo_anterior].freeze

  def initialize(importacao)
    @importacao = importacao
    @conta = importacao.account
  end

  # Entrega, bloco a bloco, um CampoQueVolta por campo ainda não devolvido.
  def em_blocos(tamanho: BLOCO)
    pendentes.select(*COLUNAS).find_in_batches(batch_size: tamanho) { |registros| yield montar(registros) }
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
    procuradas = procurado.entre(registros.select(&:de_contato?).map(&:contact_id))
    registros.map do |registro|
      id = registro.contact_id
      campo(registro, pessoas[id], ganhou: ganharam.include?(id), procurada: procuradas.include?(id))
    end
  end

  def procurado
    @procurado ||= Relacionamentos::Trazer::QuemFoiProcurado.new(@conta.id, desde: @importacao.created_at)
  end

  # Sem telefone de empresa no bloco, nada é consultado (e Empresas pode nem existir na instalação).
  def das_empresas(registros)
    return [] if registros.empty?

    linhas = @importacao.campaign_import_rows.where(id: registros.map(&:campaign_import_row_id)).where.not(company_id: nil)
    empresa_da_linha = linhas.pluck(:id, :company_id).to_h
    empresas = @conta.companies.where(id: empresa_da_linha.values.uniq).index_by(&:id)
    registros.map { |registro| campo(registro, empresas[empresa_da_linha[registro.campaign_import_row_id]]) }
  end

  def campo(registro, alvo, ganhou: false, procurada: false)
    Relacionamentos::Trazer::CampoQueVolta.new(registro, alvo: alvo, desde: @importacao.created_at, ganhou: ganhou, procurada: procurada)
  end

  def quem_ganhou(pessoas)
    return Set.new if pessoas.empty?

    ganhos = Crm::Card.com_desfecho(:won).where(account_id: @conta.id, contact_id: pessoas, closed_at: @importacao.created_at..)
    ganhos.distinct.pluck(:contact_id).to_set
  end
end
