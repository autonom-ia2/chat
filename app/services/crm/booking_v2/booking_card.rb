# O card em que a reserva da página (Crm::BookingV2::Booker) põe a reunião. Roda dentro das travas do Booker.
#
# Ordem: o card do convite, quando quem chama passou um; senão o card aberto do contato no funil da página (o Kanban não
# mostra a pessoa duas vezes); senão um card novo. O card leva a conversa de quem chama ou, sem ela, a mais recente do
# contato numa caixa da página (G47, #2755): a automação do card precisa de por onde falar com ele. Primeiro a caixa dos
# avisos (o WhatsApp que a página usa com o cliente, escolhido na tela); depois a caixa da agenda (`inbox`, a do
# calendário). O card que já existe só ganha a conversa quando ainda não tem uma; a que ele tem nunca é trocada.
class Crm::BookingV2::BookingCard
  # `conversation`: a conversa de quem chama, já conferida pelo Booker (mesma conta, mesmo telefone); pode faltar.
  def initialize(profile:, contact:, target:, host:, source:, fallback_name:, card: nil, conversation: nil) # rubocop:disable Metrics/ParameterLists
    @profile = profile
    @account = profile.account
    @contact = contact
    @target = target
    @host = host
    @source = source
    @fallback_name = fallback_name
    @card = card
    @conversation = conversation
  end

  # O card e se ele foi criado agora (o Booker avisa o Kanban do card novo depois do commit).
  def perform
    existing = @card || open_card
    return [link_conversation(existing), false] if existing

    [create!, true]
  end

  private

  # O card sem conversa ganha a da reserva, como principal, do mesmo jeito que o Creator liga a do card novo. A conversa
  # de outro contato não entra.
  def link_conversation(card)
    conversation = card.conversation_id.blank? && booking_conversation
    return card unless conversation && conversation.contact_id == card.contact_id

    card.update!(conversation_id: conversation.id, inbox_id: card.inbox_id || conversation.inbox_id)
    link = Crm::CardConversation.find_or_create_by!(account: @account, card: card, conversation: conversation)
    link.update!(is_primary: true) unless link.is_primary?
    card
  end

  def booking_conversation = @conversation || conversation_in_page_inboxes

  def open_card
    @account.crm_cards.active.where(contact_id: @contact.id, pipeline_id: @target[:pipeline_id]).order(updated_at: :desc).first
  end

  def create!
    conversation = booking_conversation
    Crm::Cards::Creator.new(
      account: @account, user: nil,
      params: {
        pipeline_id: @target[:pipeline_id], stage_id: @target[:stage_id], contact_id: @contact.id, owner_id: @host.id,
        conversation_id: conversation&.id, inbox_id: conversation&.inbox_id,
        title: "#{@contact.name.presence || @fallback_name} - #{@profile.title.presence || default_title}".first(255),
        currency: 'BRL', source: @source
      }
    ).perform
  end

  # O título do card da página sem título, na língua da conta.
  def default_title = I18n.t('crm.booking_v2.card.default_title', locale: Crm::BookingV2::LocationLabel.locale(@account))

  # Página sem caixa: nenhuma.
  def conversation_in_page_inboxes
    [@profile.notice_inbox_id, @profile.inbox_id].compact.uniq.lazy.filter_map do |inbox_id|
      @account.conversations.where(inbox_id: inbox_id, contact_id: @contact.id).order(last_activity_at: :desc, id: :desc).first
    end.first
  end
end
