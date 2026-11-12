# Os cards da ficha de Relacionamentos (#2895) no formato da tela: título, funil, etapa, valor em reais e a situação em
# palavra. Recebe os cards que quem pede enxerga no CRM (policy_scope de Crm::Card, com o acesso por funil); o valor só
# vai para quem pode ver valor de venda (Crm::ValorDeVenda, #2075). Na ficha da empresa cada card diz de quem é.
# Arquivado fica de fora, como no perfil do contato de hoje (Crm::ProfileOpportunitiesController, resultado "active").
class Relacionamentos::Ficha::Cards
  # A tela mostra todos os cards de uma vez, um botão por card, sem "mostrar mais": 50 é bem mais do que uma pessoa ou
  # uma empresa pequena junta, e segura a resposta de uma empresa com centenas.
  TETO = 50
  # As palavras do CRM em pt_BR (crm.json: "Ganhos", "Perdidos", "Resolvidos", "Cancelados"), no singular e sem acento.
  SITUACOES = { 'open' => 'aberto', 'won' => 'ganho', 'lost' => 'perdido', 'resolved' => 'resolvido', 'cancelled' => 'cancelado' }.freeze
  ABERTOS_PRIMEIRO = "(crm_cards.status = #{Crm::Card.statuses[:open]}) DESC, crm_cards.created_at DESC, crm_cards.id DESC".freeze
  CENTAVOS_POR_REAL = 100

  def initialize(cards, account_user, com_pessoa: false)
    @cards = cards
    @account_user = account_user
    @com_pessoa = com_pessoa
  end

  def call
    @cards.where.not(status: :archived).reorder(Arel.sql(ABERTOS_PRIMEIRO)).limit(TETO).preload(*do_que_a_linha_usa).map { |card| linha(card) }
  end

  private

  def do_que_a_linha_usa
    @com_pessoa ? [:pipeline, :stage, :contact] : [:pipeline, :stage]
  end

  def linha(card)
    linha = { id: card.id, titulo: card.title, funil: card.pipeline.name, etapa: card.stage.name, valor: valor_do(card),
              situacao: SITUACOES.fetch(card.status) }
    @com_pessoa ? linha.merge(pessoa: card.contact&.name) : linha
  end

  def valor_do(card)
    card.value_cents.fdiv(CENTAVOS_POR_REAL) if Crm::ValorDeVenda.ve_o_card?(@account_user, card)
  end
end
