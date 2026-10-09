# Link por cliente do agendamento (#1190, F1-C): o botão Agendar da conversa e do card. Fica atrás da flag da
# conta (`crm_booking_v2`, 404 desligada) e da `Crm::BookingInvitePolicy`.
#
# Quem gera ou lista convites tem de ver o cliente pelas regras do próprio sistema (J8-A7): via card,
# `CardPolicy#show?`; via conversa, `ConversationPolicy#show?`; só com o contato, `ContactPolicy#show?`. Entregar
# na conversa exige vê-la: a mesma regra do envio de mensagem do Chatwoot (`Conversations::BaseController` autoriza
# `ConversationPolicy#show?`); canal com a janela de mensagens fechada recusa com `cannot_reply`. `conversation_id` é
# o número da conversa no painel (`display_id`), como nas rotas de conversa.
class Api::V1::Accounts::Crm::BookingInvitesController < Api::V1::Accounts::Crm::BaseController
  LIST_LIMIT = 5

  before_action :ensure_booking_v2_enabled
  before_action :fetch_invite, only: [:deliver, :destroy]
  before_action :authorize_invite

  rescue_from ::Crm::BookingV2::InviteError do |error|
    render_unprocessable("crm.booking_v2.#{error.message}")
  end

  def index
    contact = client_contact
    invites = contact.present? ? recent_invites(contact) : []
    render json: { payload: invites.map { |invite| serialize(invite) }, pages: pages_payload }
  end

  def create
    creator = ::Crm::BookingV2::InviteCreator.new(
      account: Current.account, user: Current.user, page_id: params[:booking_page_id].presence,
      client: { card: client_card, conversation: client_conversation, contact: client_contact_param }
    )
    invite = creator.perform
    render json: { payload: serialize(invite) }, status: creator.reused? ? :ok : :created
  end

  def deliver
    conversation = params[:conversation_id].present? ? find_conversation(params[:conversation_id]) : @invite.conversation
    raise ::Crm::BookingV2::InviteError, 'invite_invalid' if conversation.blank?

    authorize conversation, :show?
    ::Crm::BookingV2::InviteDeliverer.new(invite: @invite, user: Current.user, conversation: conversation, text: params[:text]).perform
    render json: { payload: serialize(@invite.reload) }
  end

  def destroy
    ::Crm::BookingV2::InviteCanceler.new(@invite).perform
    render json: { payload: serialize(@invite) }
  end

  private

  def ensure_booking_v2_enabled
    render json: { error: 'crm.booking_v2.disabled' }, status: :not_found unless ::Crm::Config.booking_v2_enabled?(Current.account)
  end

  def invites_scope
    policy_scope(::Crm::BookingInvite, policy_scope_class: ::Crm::BookingInvitePolicy::Scope)
  end

  def fetch_invite
    @invite = ::Crm::BookingInvite.where(account_id: Current.account.id).find(params[:id])
  end

  def authorize_invite
    authorize(@invite || ::Crm::BookingInvite, "#{action_name}?", policy_class: ::Crm::BookingInvitePolicy)
  end

  def recent_invites(contact)
    invites_scope.where(contact_id: contact.id).includes(:booking_profile, :contact, :created_by, booking_link: :agent)
                 .recent_first.limit(LIST_LIMIT)
  end

  # Cliente pedido: card, depois conversa, depois contato. Cada um é autorizado pela policy do sistema.
  def client_contact
    client_card&.contact || client_conversation&.contact || client_contact_param
  end

  def client_card
    return if params[:card_id].blank?

    @client_card ||= Current.account.crm_cards.find(params[:card_id]).tap { |card| authorize card, :show? }
  end

  def client_conversation
    return if params[:conversation_id].blank?

    @client_conversation ||= find_conversation(params[:conversation_id]).tap { |conversation| authorize conversation, :show? }
  end

  def client_contact_param
    return if params[:contact_id].blank?

    @client_contact_param ||= Current.account.contacts.find(params[:contact_id]).tap { |contact| authorize contact, :show? }
  end

  def find_conversation(display_id)
    Current.account.conversations.find_by!(display_id: display_id)
  end

  def invite_pages
    @invite_pages ||= ::Crm::BookingV2::InvitePages.new(Current.account)
  end

  def pages_payload
    invite_pages.usable.map { |page| { id: page.id, title: page.title } }
  end

  def serialize(invite)
    ::Crm::BookingV2::InviteSerializer.new(invite, pages: invite_pages).as_json
  end
end
