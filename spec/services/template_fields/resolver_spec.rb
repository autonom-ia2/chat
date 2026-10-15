require 'rails_helper'

RSpec.describe TemplateFields::Resolver do
  let(:account) { create(:account, locale: 'pt_BR', name: 'Clínica Bem-Estar') }

  describe '.for_meeting' do
    let(:world) { build_booking_world(account: account) }
    let(:meeting) { create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z')) }
    let(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'panel') }

    around do |example|
      with_modified_env('FRONTEND_URL' => 'https://app.example.com') do
        travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
      end
    end

    it 'fills the approved notices exactly like the scheduling does, in the same order' do
      resolver = described_class.for_meeting(meeting, invite: invite)
      expected = Crm::BookingV2::Notices::Text.new(meeting: meeting, invite: invite, kind: 'booked').template_values

      expect(resolver.values_for(TemplateFields::MeetingResolver::NOTICE_KEYS)).to eq(expected)
      expect(expected).to eq(['Marcos', '20/10 às 10:00', invite.url])
    end

    it 'reads date and time apart in the meeting time zone, plus the account' do
      resolver = described_class.for_meeting(meeting, invite: invite)

      expect(resolver.value('horario.data')).to eq('20/10/2026')
      expect(resolver.value('horario.hora')).to eq('10:00')
      expect(resolver.value('minha_empresa.nome')).to eq('Clínica Bem-Estar')
      expect(resolver.keys).not_to include('publico.Plano', 'atendente.nome')
    end

    # The invitee is the customer: the card of the meeting goes only when the template asks for one of its fields.
    it 'leaves the deal out unless the template asks for it' do
      expect(described_class.for_meeting(meeting, invite: invite).keys.select { |key| key.start_with?('negocio.') }).to be_empty
      expect(described_class.for_meeting(meeting, invite: invite).value('negocio.titulo')).to be_nil

      asked = described_class.for_meeting(meeting, invite: invite, requested_keys: %w[cliente.primeiro_nome negocio.titulo])
      expect(asked.value('negocio.titulo')).to eq(world.card.title)
    end

    # #1518/#1524: the dynamic URL button of a template is "<base>/b/{{1}}"; the code fills {{1}} and gives back the
    # same management link, which itself stays exactly as before.
    it 'reads the management link code, which rebuilds the very same management link' do
      resolver = described_class.for_meeting(meeting, invite: invite)
      code = resolver.value('horario.link_codigo')

      expect(resolver.value('horario.link_gestao')).to eq(invite.url)
      expect(resolver.value('horario.link_gestao')).to eq("https://app.example.com/b/#{invite.code}")
      expect(code).to eq(invite.code)
      expect('https://app.example.com/b/{{1}}'.sub('{{1}}', code)).to eq(resolver.value('horario.link_gestao'))
    end

    it 'has no management link without an invite' do
      expect(described_class.for_meeting(meeting).value('horario.link_codigo')).to be_nil
      expect(described_class.for_meeting(meeting).value('horario.link_gestao')).to be_nil
      expect(described_class.for_meeting(meeting).value('cliente.primeiro_nome')).to eq('Marcos')
    end
  end

  describe '.for_card' do
    it 'adds the person who sends when there is one' do
      world = build_booking_world(account: account)
      sender = create(:user, account: account, role: :agent, name: 'Paulo Lima').tap { |user| user.update!(display_name: 'Paulo') }

      expect(described_class.for_card(world.card).keys).not_to include('atendente.nome')
      expect(described_class.for_card(world.card, attendant: sender).value('atendente.nome')).to eq('Paulo')
      expect(described_class.for_card(world.card).value('cliente.primeiro_nome')).to eq('Marcos')
    end
  end

  describe '.for_audience' do
    it 'sums contact, account and the spreadsheet row' do
      contact = create(:contact, account: account, name: 'Ana Souza')
      resolver = described_class.for_audience(
        contact: contact, columns: ['Vencimento'], values: { 'Vencimento' => '2026-10-14' }, types: { 'Vencimento' => 'data' }
      )

      expect(resolver.values_for(%w[cliente.primeiro_nome publico.Vencimento minha_empresa.nome negocio.valor]))
        .to eq(['Ana', '14/10/2026', 'Clínica Bem-Estar', nil])
    end
  end
end
