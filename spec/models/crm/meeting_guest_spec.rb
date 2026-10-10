require 'rails_helper'

RSpec.describe Crm::MeetingGuest, type: :model do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:meeting) { create_internal_meeting(world: world, starts_at: 2.days.from_now.change(min: 0)) }

  def guest(**attrs)
    described_class.new({ account: account, meeting: meeting, guest_type: :external_email }.merge(attrs))
  end

  it 'aceita convidado só com telefone' do
    expect(guest(phone_number: '+5511988887777', email: nil)).to be_valid
  end

  it 'aceita convidado só com e-mail' do
    expect(guest(email: 'ana@example.com')).to be_valid
  end

  it 'recusa convidado sem e-mail e sem telefone' do
    record = guest(email: ' ', phone_number: '')

    expect(record).not_to be_valid
    expect(record.errors[:email]).to be_present
    expect(record.errors[:phone_number]).to be_present
  end

  it 'recusa telefone que não é E.164 válido' do
    record = guest(phone_number: '11988887777')

    expect(record).not_to be_valid
    expect(record.errors[:phone_number]).to include('must be a valid E.164 number')
  end

  it 'transforma e-mail vazio em nulo, para vários convidados sem e-mail na mesma reunião' do
    first = guest(phone_number: '+5511988887777', email: '')
    first.save!
    second = guest(phone_number: '+5511977776666', email: '')

    expect(first.email).to be_nil
    expect(second).to be_valid
  end

  it 'mantém a unicidade de e-mail e de telefone dentro da mesma reunião' do
    guest(email: 'ana@example.com', phone_number: '+5511988887777').save!

    expect(guest(email: 'ana@example.com')).not_to be_valid
    expect(guest(phone_number: '+5511988887777', email: nil)).not_to be_valid
  end
end
