# Rascunhos da "Nova campanha" no servidor (#1898, épico #1784): quem só monta deixa a campanha pronta para disparar.
#
#   GET    …/campaign_journey/drafts       rascunhos pendentes da conta, do mais recente (campaign_view)
#   GET    …/campaign_journey/drafts/:id   um rascunho (campaign_view)
#   POST   …/campaign_journey/drafts       { draft: { title, channel, email_campaign_id, payload } } (campaign_manage)
#   PATCH  …/campaign_journey/drafts/:id   os mesmos campos (campaign_manage)
#   DELETE …/campaign_journey/drafts/:id   o autor, ou quem dispara (CampaignJourneyDraftPolicy#destroy?)
#
# Disparar não passa por aqui: é o POST de campaign_journey/campaigns com `draft_id` (Oficial, SMS, API), ou o
# send_now/schedule do e-mail. Os dois apagam o rascunho depois do envio. O e-mail que já saiu de rascunho some da
# lista (CampaignJourneyDraft.pending). CAMPAIGN_JOURNEY_ENABLED desligado → 404.
class Api::V1::Accounts::CampaignJourney::DraftsController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 100

  before_action :ensure_campaign_journey_enabled
  before_action :fetch_draft, only: [:show, :update, :destroy]

  def index
    authorize(CampaignJourneyDraft)
    drafts = account_drafts.pending.includes(:user).order(updated_at: :desc).limit(LIST_LIMIT)
    render json: { payload: drafts.map { |draft| present(draft) } }
  end

  def show
    render json: { payload: present(@draft) }
  end

  def create
    authorize(CampaignJourneyDraft)
    return render_invalid_payload unless payload_object?

    draft = account_drafts.new(draft_params.merge(user: Current.user))
    save(draft, :created)
  end

  def update
    return render_invalid_payload unless payload_object?

    @draft.assign_attributes(draft_params)
    save(@draft, :ok)
  end

  def destroy
    @draft.destroy!
    head :no_content
  end

  private

  def save(draft, status)
    return render json: { payload: present(draft) }, status: status if draft.save

    render json: { error: 'campaign_journey.draft_invalid', code: 'draft_invalid', details: draft.errors.details },
           status: :unprocessable_entity
  end

  # `permit(payload: {})` jogaria fora, calado, um payload que não é objeto (lista, texto): aqui ele vira 422.
  def payload_object?
    raw = params[:draft]
    return true unless raw.respond_to?(:key?) && raw.key?(:payload)

    raw[:payload].is_a?(ActionController::Parameters)
  end

  def render_invalid_payload
    render json: { error: 'campaign_journey.draft_invalid', code: 'draft_invalid', details: { payload: [{ error: 'invalid' }] } },
           status: :unprocessable_entity
  end

  def fetch_draft
    @draft = account_drafts.find(params[:id])
    authorize(@draft)
  end

  def account_drafts
    CampaignJourneyDraft.where(account_id: Current.account.id)
  end

  def draft_params
    params.require(:draft).permit(:title, :channel, :email_campaign_id, payload: {}).to_h
  end

  def present(draft)
    {
      id: draft.id, title: draft.title, channel: draft.channel, payload: draft.payload, email_campaign_id: draft.email_campaign_id,
      author: draft.user && { id: draft.user.id, name: draft.user.name },
      created_at: draft.created_at, updated_at: draft.updated_at
    }
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end
end
