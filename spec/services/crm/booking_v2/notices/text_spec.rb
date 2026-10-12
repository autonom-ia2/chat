require 'rails_helper'

# Texto dos avisos (#1192) e o aviso "ao marcar" da reunião marcada pela equipe (#1271): diz quem marcou só no texto
# livre; os valores do modelo aprovado não mudam.
RSpec.describe Crm::BookingV2::Notices::Text do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  # A factory sorteia um nome de exibição: aqui a pessoa não escolheu nenhum.
  let(:booker) { create(:user, account: account, role: :agent, name: 'Juliana Melo').tap { |user| user.update!(display_name: nil) } }
  let(:source) { 'panel' }
  let(:metadata) { { 'booking_profile_id' => world.profile.id, 'booked_by_user_id' => booker.id } }
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'), source: source, metadata: metadata)
  end
  let(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'panel') }

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  def text(kind = 'booked')
    described_class.new(meeting: meeting, invite: invite, kind: kind)
  end

  def stop_line
    "Para parar estes avisos: #{invite.url}?stop_notices=1"
  end

  it 'says who booked in the first notice of a meeting booked by the team' do
    expect(text.to_s).to eq(
      "Mensagem de #{account.name}\n" \
      "Oi, Marcos! Juliana marcou seu horário para 20/10 às 10:00. Para confirmar, mudar ou cancelar: #{invite.url}\n\n#{stop_line}"
    )
  end

  # #1307/#1322: o cliente pode ter falado com a IA em outro canal; o aviso diz de quem é, pelo nome do negócio (a conta).
  it 'says whose notice it is with the business name, only in the session text' do
    account.update!(name: 'Clínica Sol')

    expect(text('day_before').to_s.lines.first).to eq("Mensagem de Clínica Sol\n")
    expect(text.appendix).not_to include('Clínica Sol')
    expect(text.template_values).not_to include('Clínica Sol')
  end

  it 'keeps the approved template values as they are' do
    expect(text.template_values).to eq(['Marcos', '20/10 às 10:00', invite.url])
  end

  it 'prefers the display name the person chose' do
    booker.update!(display_name: 'Ju')

    expect(text.to_s).to start_with("Mensagem de #{account.name}\nOi, Marcos! Ju marcou seu horário para 20/10 às 10:00.")
  end

  it 'keeps the reminders as they are' do
    expect(text('day_before').to_s).to start_with("Mensagem de #{account.name}\nOi, Marcos! Lembrete: seu horário é amanhã, 20/10 às 10:00.")
  end

  context 'when the person who booked left the account' do
    let(:metadata) { { 'booking_profile_id' => world.profile.id, 'booked_by_user_id' => booker.id + 1000 } }

    it 'falls back to the usual text' do
      expect(text.to_s).to start_with("Mensagem de #{account.name}\nOi, Marcos! Seu horário está marcado para 20/10 às 10:00.")
    end
  end

  context 'when booked_by_user_id points to someone from another account' do
    let(:outsider) { create(:user, account: create(:account), name: 'Pedro Fora') }
    let(:metadata) { { 'booking_profile_id' => world.profile.id, 'booked_by_user_id' => outsider.id } }

    it 'does not use that name and falls back to the usual text' do
      expect(text.to_s).to start_with("Mensagem de #{account.name}\nOi, Marcos! Seu horário está marcado para 20/10 às 10:00.")
    end
  end

  context 'when the client booked by the link' do
    let(:source) { 'public_link' }

    it 'keeps the usual text even with someone in booked_by_user_id' do
      expect(text.to_s).to start_with("Mensagem de #{account.name}\nOi, Marcos! Seu horário está marcado para 20/10 às 10:00.")
    end
  end

  context 'when the account is in English' do
    let(:account) { create(:account, locale: 'en') }

    it 'says who booked in English' do
      expect(text.to_s).to start_with("Message from #{account.name}\nHi, Marcos! Juliana booked your appointment for 10/20 at 10:00.")
    end
  end
end
