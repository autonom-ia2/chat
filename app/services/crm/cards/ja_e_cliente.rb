# #2710, variante 2 (decisão do Rodrigo em 12/11): quem já comprou e marca uma reunião pela página de agendamento ganha um
# card novo (Crm::BookingV2::BookingCard#open_card continua só com card ativo). Esse card leva o selo "Já é cliente desde…",
# casado pelo contato: o mesmo contato tem um card ganho, e tocar no selo abre esse card, que é a compra.
#
# Só a pessoa que pode ver o card ganho recebe o selo (o alcance de Crm::CardPolicy#show?: caixa, "Só as suas" e acesso por
# funil, mais `crm_view` no EE). Sem isso, nada sai: o card continua com o selo "Cliente" de sempre, que a pessoa já via, e
# o payload não conta que existe uma compra num funil que ela não alcança. Quem não vê a base de contatos também não recebe
# (o card dela sai sem o selo "Cliente", #1849).
#
# `para(cards)` responde todos os cards de uma vez: uma consulta só para a página inteira do quadro.
class Crm::Cards::JaECliente
  # O que a página grava no card que ela cria (Crm::BookingV2::PublicBooking): link público e convite.
  ORIGENS_DO_AGENDAMENTO = %w[public_link invite].freeze

  def self.do_card(card, user:, account_user:)
    new(user: user, account: card.account, account_user: account_user).para([card])[card.id]
  end

  def initialize(user:, account:, account_user:)
    @contexto = { user: user, account: account, account_user: account_user }
  end

  # { id do card => { card_id: id do card ganho, desde: epoch em segundos } }, só dos cards que levam o selo.
  def para(cards)
    candidatos = cards.select { |card| candidato?(card) }
    return {} if candidatos.empty? || !pode_ler?

    ganhos = ganho_mais_recente_por_contato(candidatos.map(&:contact_id).uniq)
    candidatos.each_with_object({}) do |card, selos|
      selos[card.id] = selo(card, *ganhos[card.contact_id]) if ganhos.key?(card.contact_id)
    end
  end

  private

  # "Desde" é quando o contato virou cliente; sem essa data, quando a compra fechou.
  def selo(card, ganho_id, fechado_em)
    { card_id: ganho_id, desde: (card.contact.customer_since || fechado_em)&.to_i }
  end

  # O selo fica no lugar do "Cliente": só no card aberto que a página criou, com o contato marcado como cliente.
  def candidato?(card)
    card.open? && ORIGENS_DO_AGENDAMENTO.include?(card.source) && card.contact&.customer?
  end

  def pode_ler?
    Crm::CardPolicy.new(@contexto, Crm::Card).index? &&
      Crm::Cards::ContactReading.full?(user: @contexto[:user], account_user: @contexto[:account_user])
  end

  # A compra mais recente de cada contato entre os cards que a pessoa vê.
  def ganho_mais_recente_por_contato(contact_ids)
    Pundit.policy_scope!(@contexto, Crm::Card).won.where(contact_id: contact_ids)
          .order(Crm::Card.arel_table[:closed_at].desc.nulls_last, id: :desc)
          .pluck(:contact_id, :id, :closed_at)
          .each_with_object({}) { |(contact_id, id, fechado_em), ganhos| ganhos[contact_id] ||= [id, fechado_em] }
  end
end
