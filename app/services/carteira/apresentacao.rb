# Um seguro no formato que as telas da carteira leem (E4, #2897): a lista da aba Seguros, o bloco da ficha, o painel da
# conversa e a gaveta do seguro recebem o mesmo objeto. As chaves são as da demonstração da tela (carteiraFonte.js).
#
# O selo e os dias vêm prontos, no dia de hoje da conta: a tela não calcula com a hora do navegador. Começo e fim da
# vigência vão como AAAA-MM-DD (data sem hora; em segundos o dia mudaria com o fuso de quem lê). O que é instante (quando
# chegou, quando foi cancelado) vai em segundos, como no resto de Relacionamentos. O valor vai em reais.
#
# A renovação (E5, #2898): `renovadoEm`, o motivo de não ter renovado (`motivo` da lista, `motivoEscrito` quando é
# "outro"), `apoliceNova` (este seguro é a apólice nova de um anterior) e `renovacao`, o card de renovação que o seguro
# mostra: o id do card, o nome do funil e da etapa, como terminou (`renovou`, `nao_renovou` ou nulo) e quem cuida (o
# nome e o id do dono do card). `renovacao` é nulo sem card e quando ele foi tirado do quadro.
#
# O documento do segurado fica nulo até a decisão de onde o CPF e o CNPJ moram. O que é das próximas entregas (parcela,
# endosso, seguro de outra corretora) vem vazio, com a chave presente: as peças da tela leem essas chaves e somem por
# dado ausente.
class Carteira::Apresentacao
  DAS_PROXIMAS_ENTREGAS = { parcelaAbertaEm: nil, endosso: nil, deFora: false, corretora: '', lembreteEm: nil }.freeze
  RENOVOU = 'renovou'.freeze
  NAO_RENOVOU = 'nao_renovou'.freeze

  def initialize(account)
    @hoje = Carteira::Selo.hoje(account)
  end

  def de(apolice)
    do_seguro(apolice).merge(da_situacao(apolice), da_renovacao(apolice), DAS_PROXIMAS_ENTREGAS)
  end

  # Na ordem em que chegaram: quem pede a lista já ordenou.
  def de_cada(apolices)
    apolices.map { |apolice| de(apolice) }
  end

  # O bloco Seguros da ficha: o que pede atenção primeiro.
  def por_urgencia(apolices)
    de_cada(Carteira::Selo.por_urgencia(apolices, hoje: @hoje))
  end

  private

  def do_seguro(apolice)
    { id: apolice.id, pessoaId: apolice.contact_id, pessoa: pessoa(apolice.contact), segurado: segurado(apolice),
      tipo: apolice.tipo, ramoOriginal: apolice.ramo_original, seguradora: apolice.seguradora, numero: apolice.numero,
      valor: Carteira::Campos.em_reais(apolice.valor_centavos), bem: apolice.bem,
      comeca: apolice.inicio_vigencia&.iso8601, termina: apolice.fim_vigencia.iso8601 }
  end

  def da_situacao(apolice)
    { selo: Carteira::Selo.de(apolice, hoje: @hoje), dias: Carteira::Selo.dias(apolice, hoje: @hoje), origem: origem(apolice),
      temPdf: apolice.pdf.attached?, canceladoEm: apolice.cancelado_em&.to_i, corrigidoAMao: apolice.corrigido_a_mao }
  end

  def da_renovacao(apolice)
    { renovadoEm: apolice.renovado_em&.to_i, motivo: apolice.motivo_nao_renovou, motivoEscrito: apolice.motivo_escrito,
      apoliceNova: apolice.apolice_anterior_id.present?, renovacao: renovacao(apolice) }
  end

  def renovacao(apolice)
    card = apolice.crm_card
    return if card.nil? || apolice.renovacao_card_removido_em

    { cardId: card.id, funil: card.pipeline.name, etapa: card.stage.name, desfecho: desfecho(apolice),
      cuida: card.owner&.name, cuidaId: card.owner_id }
  end

  def desfecho(apolice)
    return RENOVOU if apolice.renovado_em

    NAO_RENOVOU if apolice.nao_renovou_em
  end

  def pessoa(contato)
    { id: contato.id, name: contato.name, phone_number: contato.phone_number, opted_out_at: contato.opted_out_at&.to_i,
      blocked: contato.blocked, contact_type: contato.contact_type, thumbnail: contato.avatar_url }
  end

  def segurado(apolice)
    empresa = apolice.company
    return { tipo: 'empresa', id: empresa.id, nome: empresa.name, documento: nil } if empresa

    { tipo: 'pessoa', id: apolice.contact_id, nome: apolice.contact.name, documento: nil }
  end

  def origem(apolice)
    { tipo: apolice.origem, arquivo: apolice.campaign_import&.source_filename, em: apolice.created_at.to_i }
  end
end
