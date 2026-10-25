# Funções personalizadas, lote 2 (#1794): com `meta_ads_view`, quem não é administrador vê os Anúncios. Os números
# do painel são da conta; as listas que levam a uma conversa (o caminho do dinheiro, as propostas do anúncio e as
# propostas paradas do consultor) mostram só as conversas que a pessoa já veria: a regra da lista de conversas
# (caixa, funil e função, Conversations::PermissionFilterService) e a do CRM (caixa "só as atribuídas",
# Crm::Conversations::Visibility). O administrador vê todas. Os valores de venda em R$ seguem a mesma pessoa (#2075).
class Crm::MetaAds::VisibleConversations
  def initialize(account:, account_user:)
    @account = account
    @account_user = account_user
    @user = account_user&.user
  end

  # A pessoa do pedido em andamento (controllers).
  def self.current
    new(account: Current.account, account_user: Current.account_user)
  end

  # O subconjunto visível dos ids pedidos, como Set. Sem pessoa (pedido sem usuário), nenhum.
  def ids(conversation_ids)
    candidates = Array(conversation_ids).compact.uniq
    return Set.new if candidates.empty? || @user.nil?

    scope = Conversation.where(account_id: @account.id, id: candidates)
    by_list = Conversations::PermissionFilterService.new(scope, @user, @account).perform.pluck(:id)
    crm_visibility.scope(Conversation.where(id: by_list)).pluck(:id).to_set
  end

  # O Advice do consultor com os cards das propostas paradas reduzidos às conversas visíveis.
  def advice(advice)
    return advice if advice.blank? || advice[:actions].blank?

    visible = ids(advice[:actions].flat_map { |action| Array(action[:cards]).pluck(:conversation_id) })
    advice.merge(actions: advice[:actions].map do |action|
      action.merge(cards: Array(action[:cards]).select { |card| visible.include?(card[:conversation_id]) })
    end)
  end

  # Valores de venda em R$ (#2075): seguem o Crm::ValorDeVenda (Crm::MetaAds::Panel::SalesValue).
  def sales_values?
    @sales_values = Crm::ValorDeVenda.ve?(@account_user) unless defined?(@sales_values)
    @sales_values
  end

  # card: qualquer um com `owner_id` (o Crm::Card ou o card da coorte do painel).
  def card_value?(card)
    sales_values? || Crm::ValorDeVenda.dono?(@account_user, card)
  end

  private

  def crm_visibility
    Crm::Conversations::Visibility.new(account: @account, user: @user, account_user: @account_user)
  end
end
