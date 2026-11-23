# A compra vira carimbo (#3100). Roda logo depois de Relacionamentos::Compras::Recalcular, no mesmo job e para as
# mesmas pessoas (Relacionamentos::Compras::RecalcularJob): o card ganho, desfeito, apagado, com outro valor ou levado
# para outra pessoa. Não é outro caminho de "card ganho": é o mesmo evento, com a mesma trava da conta
# (pg_advisory_xact_lock da Recalcular), então a venda e a rotina diária passam uma de cada vez.
#
# Para cada pessoa, compara os cards ganhos dela com as compras já dadas (Fidelidade::Movimento de origem no card):
# - card ganho que conta (Fidelidade::Programa#conta_a_compra?: cartão ligado, moeda do cartão, fechado depois de
#   ligar) e sem compra aberta: dá os carimbos (`da_compra`, sem troco), na vez seguinte daquele card;
# - compra aberta de card que não é mais ganho da pessoa (reaberto, perdido, apagado, levado para outra pessoa) ou que
#   mudou de valor ou de moeda: estorna. Com o valor novo, se o card ainda conta, dá de novo na vez seguinte.
# Rodar de novo não muda nada: o que já foi dado não é dado outra vez, e o índice único segura duas execuções.
#
# `contact_ids` nil: a conta inteira (a rotina diária), em lotes, cada lote na sua transação. Quem completou o cartão
# dispara o gatilho depois do commit (Fidelidade::CartaoCompleto).
class Fidelidade::DarPelaCompra
  CARD = 'Crm::Card'.freeze
  LOTE = 200

  def initialize(account, contact_ids: nil)
    @account = account
    @contact_ids = contact_ids&.compact&.uniq
  end

  def call
    @programa = Fidelidade::Programa.da_conta(@account)
    return unless @programa

    pessoas.each_slice(LOTE) do |lote|
      completos = Fidelidade::Movimento.transaction do
        travar_a_conta
        @account.contacts.where(id: lote).order(:id).filter_map { |contato| acertar(contato) }
      end
      Fidelidade::CartaoCompleto.avisar(@account, completos)
    end
  end

  private

  def travar_a_conta
    trava = Relacionamentos::Compras::Recalcular::TRAVA
    Fidelidade::Movimento.connection.execute(
      Fidelidade::Movimento.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?, ?)', trava, @account.id])
    )
  end

  # A conta inteira: quem tem card ganho depois de ligar o cartão e quem já tem compra dada.
  def pessoas
    return @contact_ids if @contact_ids

    desde = @programa.ligado_em
    com_venda = desde ? ganhos.where(closed_at: desde..).distinct.pluck(:contact_id) : []
    (com_venda + Fidelidade::Movimento.where(programa_id: @programa.id, tipo: Fidelidade::Movimento::COMPRA).distinct.pluck(:contact_id)).uniq
  end

  def ganhos
    Crm::Card.com_desfecho(:won).where(account_id: @account.id).where.not(contact_id: nil).where.not(closed_at: nil)
  end

  # Acerta as compras de uma pessoa. Devolve [contato, movimento] quando ela completou o cartão nesta passada.
  def acertar(contato)
    carteira = Fidelidade::Carteira.new(@programa, contato)
    cards = ganhos.where(contact_id: contato.id).index_by(&:id)
    dadas = compras_dadas(contato)
    ultimo = (cards.keys | dadas.keys).sort.filter_map { |card_id| acertar_card(carteira, cards[card_id], card_id, dadas[card_id]) }.last
    [contato, ultimo] if ultimo && carteira.completou?
  end

  # { card_id => movimentos de compra e estorno do card } da pessoa.
  def compras_dadas(contato)
    Fidelidade::Movimento.da_pessoa(@programa, contato.id).where(origem_type: CARD, tipo: Fidelidade::Movimento::DO_CARD)
                         .group_by(&:origem_id)
  end

  # Devolve a compra dada agora, ou nil.
  def acertar_card(carteira, card, card_id, movimentos)
    movimentos = Array(movimentos)
    aberta = compra_aberta(movimentos)
    if aberta && !vale_ainda?(aberta, card)
      estornar(carteira, aberta, card_id)
      aberta = nil
    end
    return if aberta || card.nil? || !@programa.conta_a_compra?(card.closed_at, card.currency)

    dar(carteira, card, (movimentos.map(&:vez).max || 0) + 1)
  end

  # A compra da última vez, se ainda não foi estornada.
  def compra_aberta(movimentos)
    compra = movimentos.select { |item| item.tipo == Fidelidade::Movimento::COMPRA }.max_by(&:vez)
    return unless compra

    compra unless movimentos.any? { |item| item.tipo == Fidelidade::Movimento::ESTORNO && item.vez == compra.vez }
  end

  def vale_ainda?(compra, card)
    card.present? && card.value_cents == compra.valor_centavos && card.currency == compra.moeda
  end

  def estornar(carteira, compra, card_id)
    carteira.sair(tipo: Fidelidade::Movimento::ESTORNO, quantos: compra.quantos, de: compra, origem_type: CARD,
                  origem_id: card_id, vez: compra.vez, valor_centavos: compra.valor_centavos, moeda: compra.moeda)
  end

  def dar(carteira, card, vez)
    quantos = @programa.da_compra(card.value_cents)
    return if quantos.zero?

    carteira.entrar(tipo: Fidelidade::Movimento::COMPRA, quantos: quantos, agora: card.closed_at, origem: card, vez: vez,
                    valor_centavos: card.value_cents, moeda: card.currency)
  end
end
