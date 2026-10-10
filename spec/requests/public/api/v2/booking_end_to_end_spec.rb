require 'rails_helper'

# RA-02 / J2-A1: conta SEM Google/Microsoft (nenhuma caixa de e-mail) cria a página pela API, publica, e o cliente
# agenda pelo link público só com nome e WhatsApp; a reunião interna aparece no card, no funil da página.
RSpec.describe 'Agendamento sem Google/MS de ponta a ponta', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:headers) { admin.create_new_auth_token }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true',
                      'FRONTEND_URL' => 'https://app.example.com') { example.run }
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features('crm_booking_v2')
    account.save!
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  # Admin cria a página a partir do modelo, sem nenhuma caixa de e-mail na conta: nasce despublicada.
  def create_page
    post "/api/v1/accounts/#{account.id}/crm/booking_pages", params: { template_key: 'sales_30' }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    created = response.parsed_body['payload']
    expect(created).to include('enabled' => false, 'calendar_inbox_id' => nil)
    created
  end

  def publish_page(created)
    get "/public/api/v2/booking/#{created['slug']}"
    expect(response.parsed_body).to include('paused' => true)

    post "/api/v1/accounts/#{account.id}/crm/booking_pages/#{created['id']}/publish", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    created['slug']
  end

  # Cliente abre a página, espera alguns segundos preenchendo (o form_token recusa menos de 2 s) e pega o próximo
  # horário. Hoje, segunda 12/10/2026, é feriado nacional (Nossa Senhora Aparecida) e a página nasce fechando
  # feriados (#1195, J3-A13): o próximo horário é o primeiro de terça.
  def open_page_and_pick_next_slot(slug)
    get "/public/api/v2/booking/#{slug}"
    page = response.parsed_body
    expect(page).to include('paused' => false, 'title' => 'Conversa de vendas de 30 min', 'agent_name' => admin.available_name)
    expect(page['locations']).to eq([{ 'type' => 'whatsapp_video', 'label' => 'Vídeo no WhatsApp', 'requires_email' => false }])

    travel 5.seconds
    get "/public/api/v2/booking/#{slug}/next_slot"
    [page['form_token'], response.parsed_body['starts_at']]
  end

  it 'publica a página e recebe a reserva com reunião interna no card' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    slug = publish_page(create_page)
    form_token, starts_at = open_page_and_pick_next_slot(slug)
    expect(starts_at).to eq('2026-10-13T09:00:00-03:00')

    post "/public/api/v2/booking/#{slug}",
         params: { name: 'Ana Souza', phone: '+55 21 98888-7777', starts_at: starts_at, company: '', form_token: form_token,
                   consent: { accepted: true } },
         as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('confirmed' => true, 'starts_at' => starts_at)

    card = account.crm_cards.find_by!(source: 'public_link')
    expect(card).to have_attributes(pipeline_id: pipeline.id, stage_id: stage.id, owner_id: admin.id)
    expect(card.contact).to have_attributes(name: 'Ana Souza', phone_number: '+5521988887777', email: nil)
    expect(Crm::Meeting.where(card_id: card.id).sole).to have_attributes(
      provider: 'internal', inbox_id: nil, online_meeting_type: 'whatsapp_video', status: 'scheduled',
      starts_at: Time.iso8601(starts_at), created_by_id: admin.id
    )
    expect(card.activities.pluck(:event_type)).to include('meeting_scheduled')
  end
end
