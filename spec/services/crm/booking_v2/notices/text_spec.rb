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
      "Oi, Marcos! Juliana marcou seu horário para 20/10 às 10:00. Para confirmar, mudar ou cancelar: #{invite.url}\n\n#{stop_line}"
    )
  end

  it 'keeps the approved template values as they are' do
    expect(text.template_values).to eq(['Marcos', '20/10 às 10:00', invite.url])
  end

  it 'prefers the display name the person chose' do
    booker.update!(display_name: 'Ju')

    expect(text.to_s).to start_with('Oi, Marcos! Ju marcou seu horário para 20/10 às 10:00.')
  end

  it 'keeps the reminders as they are' do
    expect(text('day_before').to_s).to start_with('Oi, Marcos! Lembrete: seu horário é amanhã, 20/10 às 10:00.')
  end

  context 'when the person who booked left the account' do
    let(:metadata) { { 'booking_profile_id' => world.profile.id, 'booked_by_user_id' => booker.id + 1000 } }

    it 'falls back to the usual text' do
      expect(text.to_s).to start_with('Oi, Marcos! Seu horário está marcado para 20/10 às 10:00.')
    end
  end

  context 'when booked_by_user_id points to someone from another account' do
    let(:outsider) { create(:user, account: create(:account), name: 'Pedro Fora') }
    let(:metadata) { { 'booking_profile_id' => world.profile.id, 'booked_by_user_id' => outsider.id } }

    it 'does not use that name and falls back to the usual text' do
      expect(text.to_s).to start_with('Oi, Marcos! Seu horário está marcado para 20/10 às 10:00.')
    end
  end

  context 'when the client booked by the link' do
    let(:source) { 'public_link' }

    it 'keeps the usual text even with someone in booked_by_user_id' do
      expect(text.to_s).to start_with('Oi, Marcos! Seu horário está marcado para 20/10 às 10:00.')
    end
  end

  describe 'texto próprio da página (#1354)' do
    let(:source) { 'public_link' }
    let(:own) { 'Olá, {{cliente.primeiro_nome}}! Te esperamos na {{minha_empresa.nome}} em {{horario.data_hora}}. Mude em {{horario.link_gestao}}' }

    def own_text(kind = 'booked', page: world.profile)
      described_class.new(meeting: meeting, invite: invite, kind: kind, page: page)
    end

    before { world.profile.update!(notice_texts: { 'booked' => own }) }

    it 'usa o texto do dono, preenchido pelo catálogo, e acrescenta sempre a linha de parar' do
      expect(own_text.to_s).to eq(
        "Olá, Marcos! Te esperamos na #{account.name} em 20/10 às 10:00. Mude em #{invite.url}\n\n#{stop_line}"
      )
    end

    it 'sem nome do cliente, não deixa "Olá, !"' do
      world.contact.update!(name: '+5511999998888')

      expect(own_text.to_s).to start_with('Olá! Te esperamos')
    end

    it 'aviso sem texto próprio e chamada sem página seguem o padrão' do
      expect(own_text('day_before').to_s).to start_with('Oi, Marcos! Lembrete: seu horário é amanhã')
      expect(own_text(page: nil).to_s).to start_with('Oi, Marcos! Seu horário está marcado')
    end

    it 'texto gravado que não passa mais na conferência cai no padrão, com a linha de parar, e fica no log sem o texto' do
      world.profile.update_columns(metadata: world.profile.metadata.merge('notice_texts' => { 'booked' => 'Oi {{cliente.cpf}}' })) # rubocop:disable Rails/SkipsModelValidations
      allow(Rails.logger).to receive(:warn)

      expect(own_text(page: world.profile.reload).to_s).to eq(
        "Oi, Marcos! Seu horário está marcado para 20/10 às 10:00. Para confirmar, mudar ou cancelar: #{invite.url}\n\n#{stop_line}"
      )
      expect(Rails.logger).to have_received(:warn).with(a_string_including('custom_text_fallback'))
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including('cpf'))
    end

    it 'não usa texto de página de outra conta' do
      other_account = create(:account)
      other = create_booking_profile(account: other_account, host: create(:user, account: other_account), notice_texts: { 'booked' => own })

      expect(own_text(page: other).to_s).to start_with('Oi, Marcos! Seu horário está marcado')
    end

    it 'não muda os valores do modelo aprovado nem o complemento do canal API' do
      expect(own_text.template_values).to eq(['Marcos', '20/10 às 10:00', invite.url])
      expect(own_text.appendix).to eq("20/10 às 10:00 - #{invite.url}\n\n#{stop_line}")
    end

    context 'when the team booked from the panel' do
      let(:source) { 'panel' }

      it 'usa o padrão que diz quem marcou' do
        expect(own_text.to_s).to start_with('Oi, Marcos! Juliana marcou seu horário')
      end
    end
  end

  context 'when the account is in English' do
    let(:account) { create(:account, locale: 'en') }

    it 'says who booked in English' do
      expect(text.to_s).to start_with('Hi, Marcos! Juliana booked your appointment for 10/20 at 10:00.')
    end
  end
end
