require 'rails_helper'

# Cliente desde quando (E4, #2897): quem promove sabendo a data passa `since:`, e a mais antiga vence.
RSpec.describe ContactCustomer, :aggregate_failures do
  let(:account) { create(:account, reporting_timezone: 'America/Manaus') }
  let(:contato) { create(:contact, account: account) }
  let(:fuso) { ActiveSupport::TimeZone['America/Manaus'] }
  let(:agora) { Time.zone.parse('2026-11-12 15:00') }

  around { |example| travel_to(agora) { example.run } }

  it 'sem data, vira cliente desde agora; de novo, não muda nada' do
    expect(contato.become_customer!).to be(true)
    expect([contato.reload.customer?, contato.customer_since]).to eq([true, agora])

    travel 1.day
    expect(contato.become_customer!).to be(false)
    expect(contato.reload.customer_since).to eq(agora)
  end

  it 'com a data sem hora, vira cliente desde o começo daquele dia no fuso da conta' do
    expect(contato.become_customer!(since: Date.new(2025, 6, 1))).to be(true)

    expect(contato.reload.customer_since).to eq(fuso.local(2025, 6, 1))
    expect(contato.customer_since.utc.hour).to eq(4)
  end

  it 'a data mais antiga vence, também em quem já é cliente; a mais nova e a falta de data não mudam nada' do
    contato.become_customer!(since: Date.new(2025, 6, 1))

    expect(contato.become_customer!(since: Date.new(2026, 3, 10))).to be(false)
    expect(contato.become_customer!).to be(false)
    expect(contato.reload.customer_since).to eq(fuso.local(2025, 6, 1))

    expect(contato.become_customer!(since: Date.new(2024, 1, 10))).to be(false)
    expect(contato.reload.customer_since).to eq(fuso.local(2024, 1, 10))
  end

  it 'a data no futuro vira agora' do
    contato.become_customer!(since: Date.new(2027, 1, 1))

    expect(contato.reload.customer_since).to eq(agora)
  end

  it 'quem deixou de ser cliente e volta conta como promovido de novo, com a data nova' do
    contato.become_customer!(since: Date.new(2025, 6, 1))
    contato.release_customer!

    expect(contato.become_customer!(since: Date.new(2026, 3, 10))).to be(true)
    expect(contato.reload.customer_since).to eq(fuso.local(2026, 3, 10))
  end
end
