require 'rails_helper'

# Link por cliente (#1190): código curto e sem ambiguidade, vínculos todos da mesma conta e do mesmo contato,
# estado e URL.
RSpec.describe Crm::BookingInvite, type: :model do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:other_world) { build_booking_world(account: create(:account)) }

  def build_invite(**attrs)
    described_class.new(
      { account: account, booking_profile: world.profile, contact: world.contact, created_by: world.host,
        expires_at: 7.days.from_now }.merge(attrs)
    )
  end

  def errors_for(invite, field)
    invite.validate
    invite.errors[field]
  end

  describe 'code' do
    it 'generates 8 characters without 0, O, 1, l or I and keeps them unique' do
      codes = Array.new(40) { create_booking_invite(world: world).code }

      expect(codes.uniq.size).to eq(40)
      codes.each do |code|
        expect(code.length).to eq(8)
        expect(code.chars & %w[0 O 1 l I]).to be_empty
        expect(code.chars - described_class::CODE_ALPHABET).to be_empty
      end
      expect(described_class::CODE_ALPHABET & %w[0 O 1 l I]).to be_empty
    end

    it 'draws again when the drawn code already exists' do
      taken = create_booking_invite(world: world).code
      allow(described_class).to receive(:generate_code).and_return(taken, 'ABCD2345')

      invite = create_booking_invite(world: world)

      expect(invite.code).to eq('ABCD2345')
      expect(described_class).to have_received(:generate_code).twice
    end

    it 'refuses a duplicated code set by hand' do
      taken = create_booking_invite(world: world).code

      invite = build_invite(code: taken)

      expect(invite).not_to be_valid
      expect(invite.errors[:code]).to be_present
    end
  end

  describe 'cross-account and cross-contact references' do
    it 'is valid with everything from the same account and contact' do
      conversation = create(:conversation, account: account, contact: world.contact)

      expect(build_invite(card: world.card, conversation: conversation)).to be_valid
    end

    it 'refuses a page, contact, card, conversation or meeting from another account' do
      foreign_meeting = create_internal_meeting(world: other_world, starts_at: 2.days.from_now)
      {
        booking_profile: { booking_profile: other_world.profile },
        contact: { contact: other_world.contact },
        card: { card: other_world.card },
        conversation: { conversation: create(:conversation, account: other_world.account, contact: other_world.contact) },
        meeting: { meeting: foreign_meeting }
      }.each do |field, attrs|
        invite = build_invite(**attrs)

        expect(invite).not_to be_valid, "#{field} from another account was accepted"
        expect(invite.errors[field]).to include('must belong to the same account')
      end
    end

    it 'refuses an author who is not a member of the account' do
      invite = build_invite(created_by: create(:user))

      expect(invite).not_to be_valid
      expect(invite.errors[:created_by]).to include('must belong to the same account')
    end

    it 'refuses a conversation or a card of another contact of the same account' do
      stranger = create_booking_contact(account: account, name: 'Outra Pessoa', phone: '+5511988887777')
      other_card = create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: stranger)
      other_conversation = create(:conversation, account: account, contact: stranger)

      expect(errors_for(build_invite(conversation: other_conversation), :conversation)).to include('must belong to the same contact')
      expect(errors_for(build_invite(card: other_card), :card)).to include('must belong to the same contact')
    end

    it 'refuses a personal link of another page' do
      other_page = create_booking_profile(account: account, host: world.host)
      link = other_page.agent_booking_links.create!(account: account, agent: world.host)

      expect(errors_for(build_invite(booking_link: link), :booking_link)).to include('must belong to the same booking page')
    end

    it 'accepts only the known channels' do
      expect(build_invite(channel: 'conversation')).to be_valid
      expect(build_invite(channel: 'sms')).not_to be_valid
    end
  end

  describe '#state, #active? and #url' do
    let(:invite) { create_booking_invite(world: world) }

    it 'goes from created to sent to opened' do
      expect(invite.state).to eq('created')
      invite.update!(sent_at: Time.current)
      expect(invite.state).to eq('sent')
      invite.update!(first_opened_at: Time.current)
      expect(invite.state).to eq('opened')
      expect(invite).to be_active
    end

    it 'expires after the deadline unless it was scheduled' do
      invite.update!(first_opened_at: Time.current, expires_at: 1.minute.ago)
      expect(invite.state).to eq('expired')
      expect(invite).not_to be_active

      meeting = create_internal_meeting(world: world, starts_at: 2.days.from_now)
      invite.update!(scheduled_at: 2.days.ago, meeting: meeting)
      expect(invite.state).to eq('scheduled')
      expect(invite).to be_active
    end

    it 'deixa de dar acesso 1 dia depois do fim da reunião agendada (J5-A2)' do
      meeting = create_internal_meeting(world: world, starts_at: 3.days.from_now)
      invite.update!(scheduled_at: Time.current, meeting: meeting)

      travel_to(meeting.ends_at + 23.hours) { expect(invite).to be_active }
      travel_to(meeting.ends_at + 1.day + 1.minute) { expect(invite).not_to be_active }
    end

    it 'não dá acesso a convite marcado como agendado sem reunião' do
      invite.update!(scheduled_at: Time.current)

      expect(invite).not_to be_active
    end

    it 'is canceled above everything else' do
      invite.update!(scheduled_at: Time.current, canceled_at: Time.current, expires_at: 1.minute.ago)

      expect(invite.state).to eq('canceled')
      expect(invite).not_to be_active
    end

    it 'builds the public URL from FRONTEND_URL' do
      with_modified_env('FRONTEND_URL' => 'https://app.example.com/') do
        expect(invite.url).to eq("https://app.example.com/b/#{invite.code}")
      end
    end
  end

  describe 'booking page invite settings' do
    it 'accepts a validity between 1 and 30 days and a text up to 1000 characters' do
      page = world.profile

      expect(page.invite_ttl_days).to eq(7)
      expect(page.tap { |p| p.invite_ttl_days = 30 }).to be_valid
      expect(page.tap { |p| p.invite_ttl_days = 0 }).not_to be_valid
      expect(page.tap { |p| p.invite_ttl_days = 31 }).not_to be_valid
      page.invite_ttl_days = 7
      expect(page.tap { |p| p.invite_text = 'a' * 1000 }).to be_valid
      expect(page.tap { |p| p.invite_text = 'a' * 1001 }).not_to be_valid
    end
  end
end
