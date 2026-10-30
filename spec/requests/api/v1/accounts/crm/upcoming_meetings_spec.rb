require 'rails_helper'

# Aviso ao arquivar (#2091): a próxima reunião marcada de cada card, no fuso da conta, numa consulta só.
RSpec.describe 'CRM cards upcoming meetings', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:world) { build_booking_world(account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/cards/upcoming_meetings" }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { travel_to(Time.utc(2026, 10, 22, 15, 0)) { example.run } }
  end

  def outro_card
    account.crm_cards.create!(pipeline: world.pipeline, stage: world.stage, contact: world.contact, title: 'Outro')
  end

  it 'devolve a próxima reunião marcada de cada card, no fuso da conta' do
    create_internal_meeting(world: world, starts_at: Time.utc(2026, 10, 25, 13, 0))
    create_internal_meeting(world: world, starts_at: Time.utc(2026, 10, 24, 13, 0))
    sem_reuniao = outro_card

    get url, params: { card_ids: [world.card.id, sem_reuniao.id] }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to eq(
      'timezone' => 'America/Sao_Paulo',
      'cards' => [{ 'card_id' => world.card.id, 'starts_at' => '2026-10-24T10:00:00-03:00' }]
    )
  end

  it 'ignora reunião cancelada ou que já passou' do
    create_internal_meeting(world: world, starts_at: 2.days.from_now, status: :canceled)
    create_internal_meeting(world: world, starts_at: 2.days.ago)

    get url, params: { card_ids: [world.card.id] }, headers: auth_headers(admin)

    expect(response.parsed_body.dig('payload', 'cards')).to eq([])
  end

  it 'não mostra reunião de card de outra conta' do
    create_internal_meeting(world: world, starts_at: 2.days.from_now)
    outra = create(:account)
    estranho = create(:user, account: outra, role: :administrator)

    get "/api/v1/accounts/#{outra.id}/crm/cards/upcoming_meetings",
        params: { card_ids: [world.card.id] }, headers: auth_headers(estranho)

    expect(response.parsed_body.dig('payload', 'cards')).to eq([])
  end

  it 'conta o lote numa consulta só' do
    cards = Array.new(3) { outro_card }
    cards.each { |card| create_internal_meeting(world: world, starts_at: 2.days.from_now, card: card) }
    consultas = 0
    contador = ->(*, payload) { consultas += 1 if payload[:sql].include?('crm_meetings') }

    ActiveSupport::Notifications.subscribed(contador, 'sql.active_record') do
      get url, params: { card_ids: cards.map(&:id) }, headers: auth_headers(admin)
    end

    expect(response.parsed_body.dig('payload', 'cards').size).to eq(3)
    expect(consultas).to eq(1)
  end
end
