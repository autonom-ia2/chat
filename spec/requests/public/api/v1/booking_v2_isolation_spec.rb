require 'rails_helper'

# A API pública antiga (v1) não pode servir nem reservar página nova (#1188): a página nova só existe pela v2,
# com form_token, limites por telefone e sem caixa de e-mail. Aqui a v1 trata o slug novo como inexistente.
RSpec.describe 'Public booking v1 x páginas novas', type: :request do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }

  around { |example| with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run } }

  it 'devolve 404 para o slug de uma página nova' do
    get "/public/api/v1/booking/#{world.profile.slug}"

    expect(response).to have_http_status(:not_found)
  end

  # Controle positivo: o mesmo endpoint segue servindo a página antiga; o 404 acima é por ser página nova.
  it 'continua servindo a página antiga com caixa de calendário' do
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    legacy = create_booking_profile(account: account, host: world.host, page_version: Crm::AgentBookingProfile::LEGACY_PAGE,
                                    inbox: inbox, locations: [], title: 'Página antiga')

    get "/public/api/v1/booking/#{legacy.slug}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('slug' => legacy.slug, 'title' => 'Página antiga')
  end

  it 'não confirma reserva de página nova, nem com token assinado para ela' do
    token = Crm::Calendar::PublicBookingService.message_verifier.generate(
      { 'p' => world.profile.id, 'n' => 'Ana', 'e' => 'ana@example.com', 's' => 2.days.from_now.change(hour: 13).iso8601 },
      expires_in: 1.hour
    )

    post "/public/api/v1/booking/#{world.profile.slug}/confirm", params: { token: token }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'booking_failed')
    expect(account.crm_meetings.count).to eq(0)
  end

  it 'não reserva por página nova' do
    post "/public/api/v1/booking/#{world.profile.slug}",
         params: { name: 'Ana', email: 'ana@example.com', starts_at: 2.days.from_now.change(hour: 10).iso8601, form_loaded_at: 0 }

    expect(response).to have_http_status(:not_found)
    expect(account.crm_meetings.count).to eq(0)
  end

  it 'não serve link individual de uma página nova' do
    agent = create(:user, account: account, role: :agent)
    world.profile.update!(assignment_mode: :per_agent)
    link = account.crm_agent_booking_links.create!(booking_profile: world.profile, agent: agent)

    get "/public/api/v1/booking/#{link.slug}"

    expect(response).to have_http_status(:not_found)
  end
end
