require 'rails_helper'

# Link por cliente (#1190): escolha da página e do link individual, contato vindo do card/conversa, validade,
# canal, reaproveitamento do convite ativo e recusa sem página.
RSpec.describe Crm::BookingV2::InviteCreator do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Rafa Souza') }

  def create_invite(user: world.host, page_id: nil, **client)
    described_class.new(account: account, user: user, page_id: page_id, client: client).perform
  end

  describe 'page choice' do
    it 'uses the requested page when it is published and usable' do
      second = create_booking_profile(account: account, host: world.host, title: 'Visita')

      invite = create_invite(page_id: second.id.to_s, card: world.card)

      expect(invite.booking_profile).to eq(second)
    end

    it 'without a request, prefers the page where the person is the fixed host' do
      world.profile
      mine = create_booking_profile(account: account, host: agent, title: 'Minha')

      invite = create_invite(user: agent, card: world.card)

      expect(invite.booking_profile).to eq(mine)
      expect(invite.booking_link).to be_nil
    end

    it 'in a per_agent page uses the personal link of the person' do
      page = create_booking_profile(account: account, host: world.host, title: 'Equipe')
      Crm::BookingV2::PagePeople.new(page).assign!([world.host.id, agent.id])
      world.profile.update!(enabled: false)

      invite = create_invite(user: agent, card: world.card)

      expect(invite.booking_profile).to eq(page)
      expect(invite.booking_link).to eq(page.agent_booking_links.find_by(agent_id: agent.id))
    end

    it 'falls back to the first published page when the person attends none' do
      invite = create_invite(user: agent, card: world.card)

      expect(invite.booking_profile).to eq(world.profile)
    end

    it 'ignores paused pages, legacy pages and pages whose host left the account' do
      world.profile.update!(enabled: false)
      gone = create(:user, account: account, role: :agent)
      orphan = create_booking_profile(account: account, host: gone)
      AccountUser.find_by(account: account, user: gone).destroy!

      expect { create_invite(card: world.card) }.to raise_error(Crm::BookingV2::InviteError, 'no_page')
      expect { create_invite(card: world.card, page_id: orphan.id) }.to raise_error(Crm::BookingV2::InviteError, 'no_page')
      expect(Crm::BookingInvite.count).to eq(0)
    end

    it 'raises no_page (an ArgumentError) for a page of another account' do
      foreign = build_booking_world(account: create(:account)).profile

      expect { create_invite(card: world.card, page_id: foreign.id) }.to raise_error(ArgumentError, 'no_page')
    end
  end

  describe 'contact, validity and channel' do
    it 'takes the contact from the card, validity from the page and channel copy without conversation' do
      world.profile.update!(invite_ttl_days: 3)

      # O esperado é calculado dentro do mesmo tempo congelado: com a máquina carregada, comparar com o relógio de depois
      # passava de 1 segundo e o teste ficava instável.
      invite, expected_expiry = freeze_time { [create_invite(card: world.card), 3.days.from_now] }

      expect(invite).to have_attributes(contact_id: world.contact.id, card_id: world.card.id, created_by_id: world.host.id,
                                        channel: 'copy', conversation_id: nil)
      expect(invite.expires_at).to be_within(1.second).of(expected_expiry)
    end

    it 'takes the contact from the conversation and uses the conversation channel' do
      conversation = create(:conversation, account: account, contact: world.contact)

      invite = create_invite(conversation: conversation)

      expect(invite).to have_attributes(contact_id: world.contact.id, conversation_id: conversation.id, channel: 'conversation')
    end

    it 'refuses a conversation of another contact and a contact that differs from the card' do
      stranger = create_booking_contact(account: account, name: 'Outra', phone: '+5511977776666')
      conversation = create(:conversation, account: account, contact: stranger)

      expect { create_invite(card: world.card, conversation: conversation) }.to raise_error(Crm::BookingV2::InviteError, 'invite_invalid')
      expect { create_invite(card: world.card, contact: stranger) }.to raise_error(Crm::BookingV2::InviteError, 'invite_invalid')
      expect { create_invite }.to raise_error(Crm::BookingV2::InviteError, 'invite_invalid')
    end
  end

  describe 'one active invite per person, contact and page' do
    it 'returns the active invite of the same page instead of creating another' do
      first_creator = described_class.new(account: account, user: world.host, client: { card: world.card })
      first = first_creator.perform
      again = described_class.new(account: account, user: world.host, client: { contact: world.contact })

      expect(again.perform).to eq(first)
      expect(again).to be_reused
      expect(first_creator).not_to be_reused
      expect(Crm::BookingInvite.count).to eq(1)
    end

    it 'still refuses a conversation of another contact when an active invite would be reused' do
      create_invite(card: world.card)
      stranger = create_booking_contact(account: account, name: 'Outra', phone: '+5511944443333')
      conversation = create(:conversation, account: account, contact: stranger)

      expect { create_invite(card: world.card, conversation: conversation) }.to raise_error(Crm::BookingV2::InviteError, 'invite_invalid')
    end

    it 'cancels the active invites of the person for the contact when another page is requested' do
      first = create_invite(card: world.card)
      other_person = create_invite(user: agent, card: world.card)
      second_page = create_booking_profile(account: account, host: world.host, title: 'Visita')

      second = create_invite(card: world.card, page_id: second_page.id)

      expect(second).not_to eq(first)
      expect(first.reload.canceled_at).to be_present
      expect(other_person.reload.canceled_at).to be_nil
    end

    it 'cancels the active invite and creates another when its personal link stopped working' do
      page = create_booking_profile(account: account, host: world.host, title: 'Equipe')
      Crm::BookingV2::PagePeople.new(page).assign!([world.host.id, agent.id])
      world.profile.update!(enabled: false)
      previous = create_invite(user: agent, card: world.card)
      previous.booking_link.update!(enabled: false)

      creator = described_class.new(account: account, user: agent, client: { card: world.card })
      fresh = creator.perform

      expect(creator).not_to be_reused
      expect(fresh).not_to eq(previous)
      expect(fresh).to have_attributes(booking_profile_id: page.id, booking_link_id: nil)
      expect(previous.reload.canceled_at).to be_present
    end

    it 'creates a new one when the previous is expired, canceled or scheduled' do
      %i[expires_at canceled_at scheduled_at].each do |field|
        previous = create_invite(card: world.card)
        previous.update!(field => field == :expires_at ? 1.minute.ago : Time.current)

        expect(create_invite(card: world.card)).not_to eq(previous)
      end
    end
  end
end
