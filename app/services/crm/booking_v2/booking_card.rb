# O card em que a reserva da página (Crm::BookingV2::Booker) põe a reunião. Roda dentro das travas do Booker.
#
# Ordem: o card do convite, quando quem chama passou um; senão o card aberto do contato no funil da página (o Kanban não
# mostra a pessoa duas vezes); senão um card novo. O card novo leva a conversa de quem chama ou, sem ela, a mais recente
# do contato na caixa da página (G47, #2755): a automação do card precisa de por onde falar com ele.
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
    return [existing, false] if existing

    [create!, true]
  end

  private

  def open_card
    @account.crm_cards.active.where(contact_id: @contact.id, pipeline_id: @target[:pipeline_id]).order(updated_at: :desc).first
  end

  def create!
    conversation = @conversation || conversation_in_page_inbox
    Crm::Cards::Creator.new(
      account: @account, user: nil,
      params: {
        pipeline_id: @target[:pipeline_id], stage_id: @target[:stage_id], contact_id: @contact.id, owner_id: @host.id,
        conversation_id: conversation&.id, inbox_id: conversation&.inbox_id,
        title: "#{@contact.name.presence || @fallback_name} - #{@profile.title.presence || 'Agendamento'}".first(255),
        currency: 'BRL', source: @source
      }
    ).perform
  end

  # Página sem caixa: nenhuma.
  def conversation_in_page_inbox
    return if @profile.inbox_id.blank?

    @account.conversations.where(inbox_id: @profile.inbox_id, contact_id: @contact.id).order(last_activity_at: :desc, id: :desc).first
  end
end
