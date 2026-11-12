# #2710, variante 2 (decisão do Rodrigo em 12/11): quem já comprou e marca uma reunião pela página de agendamento ganha um
# card novo (Crm::BookingV2::BookingCard#open_card continua só com card ativo). Esse card leva o selo "Já é cliente desde…",
# casado pelo contato: o mesmo contato tem um card ganho, e tocar no selo abre esse card, que é a compra.
#
# Só a pessoa que pode ver o card ganho recebe o selo (o alcance de Crm::CardPolicy#show?: caixa, "Só as suas" e acesso por
# funil, mais `crm_view` no EE). Sem isso, nada sai: o card continua com o selo "Cliente" de sempre, que a pessoa já via, e
# o payload não conta que existe uma compra num funil que ela não alcança. Quem não vê a base de contatos também não recebe
# (o card dela sai sem o selo "Cliente", #1849).
#
# `para(cards)` responde o quadro de uma pessoa: uma consulta só, uma linha por contato. O card aberto e o tempo real (um
# card, várias pessoas) passam por Crm::Cards::JaEClienteDoCard, que busca as compras uma vez e usa `entre` por pessoa.
class Crm::Cards::JaECliente
  # O que a página grava no card que ela cria (Crm::BookingV2::PublicBooking): link público e convite.
  ORIGENS_DO_AGENDAMENTO = %w[public_link invite].freeze
  # A compra mais recente primeiro; o ganho antigo sem data fica por último.
  MAIS_RECENTE = [Crm::Card.arel_table[:closed_at].desc.nulls_last, Crm::Card.arel_table[:id].desc].freeze

  # O selo fica no lugar do "Cliente": só no card aberto que a página criou, com o contato marcado como cliente.
  def self.candidato?(card)
    card.open? && ORIGENS_DO_AGENDAMENTO.include?(card.source) && card.contact&.customer?
  end

  def initialize(user:, account:, account_user:)
    @contexto = { user: user, account: account, account_user: account_user }
  end

  # { id do card => { card_id: id do card ganho, desde: epoch em segundos } }, só dos cards que levam o selo.
  def para(cards)
    candidatos = cards.select { |card| self.class.candidato?(card) }
    return {} if candidatos.empty? || !pode_ler?

    ganhos = ganho_mais_recente_por_contato(candidatos.map(&:contact_id).uniq)
    candidatos.each_with_object({}) do |card, selos|
      selos[card.id] = selo(card, *ganhos[card.contact_id]) if ganhos.key?(card.contact_id)
    end
  end

  # O selo de um card candidato, escolhendo entre compras já achadas (`ganho_ids`) só as que esta pessoa vê.
  def entre(card, ganho_ids)
    return if ganho_ids.empty? || !pode_ler?

    ganho_id, fechado_em = visiveis.where(id: ganho_ids).order(*MAIS_RECENTE).pick(:id, :closed_at)
    selo(card, ganho_id, fechado_em) if ganho_id
  end

  private

  # "Desde" é quando o contato virou cliente; sem essa data, quando a compra fechou. O topo do card usa a mesma.
  def selo(card, ganho_id, fechado_em)
    { card_id: ganho_id, desde: (card.contact.customer_since || fechado_em)&.to_i }
  end

  def pode_ler?
    Crm::CardPolicy.new(@contexto, Crm::Card).index? &&
      Crm::Cards::ContactReading.full?(user: @contexto[:user], account_user: @contexto[:account_user])
  end

  def visiveis
    Pundit.policy_scope!(@contexto, Crm::Card)
  end

  # A compra mais recente de cada contato entre os cards que a pessoa vê: uma linha por contato (DISTINCT ON).
  def ganho_mais_recente_por_contato(contact_ids)
    contato = Crm::Card.arel_table[:contact_id]
    visiveis.won.where(contact_id: contact_ids)
            .reorder(contato, *MAIS_RECENTE)
            .pluck(Arel.sql('DISTINCT ON (crm_cards.contact_id) crm_cards.contact_id'), :id, :closed_at)
            .to_h { |contact_id, id, fechado_em| [contact_id, [id, fechado_em]] }
  end
end
