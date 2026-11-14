require 'rails_helper'

# #2896 (fatia 3) — o Desfazer de "Trazer minha lista" devolve ao tipo de antes quem a lista marcou como cliente
# (Contact#revert_customer!). Marcar e desmarcar pelo painel: customers_controller_spec.rb.
# #2897 (E4) — a carteira de seguros promove dizendo desde quando (Contact#become_customer! com `since:`).
RSpec.describe ContactCustomer, :aggregate_failures do
  let(:account) { create(:account) }
  let(:desde) { Time.zone.parse('2026-03-15 12:00') }

  def cliente(**dados)
    create(:contact, account: account, **dados).tap { |contato| contato.update!(contact_type: :customer, customer_since: desde) }
  end

  describe '#revert_customer!' do
    it 'devolve o cliente ao tipo de antes e tira a data, quando o bloco confirma' do
      era_lead = cliente(phone_number: '+5511987650001')
      era_visitante = cliente(name: 'Pessoa Sem Contato')

      expect(era_lead.revert_customer!(to: 'lead') { true }).to be(true)
      expect(era_visitante.revert_customer!(to: 'visitor') { true }).to be(true)

      expect(era_lead.reload).to have_attributes(contact_type: 'lead', customer_since: nil)
      expect(era_visitante.reload).to have_attributes(contact_type: 'visitor', customer_since: nil)
    end

    it 'não mexe em quem o bloco não confirma, e o bloco vê o contato relido sob a trava' do
      contato = cliente(phone_number: '+5511987650001')
      antigo = Contact.find(contato.id)
      contato.update!(customer_since: desde + 1.day)
      visto = nil

      feito = antigo.revert_customer!(to: 'lead') do
        visto = antigo.customer_since
        false
      end

      expect(feito).to be(false)
      expect(visto).to eq(desde + 1.day)
      expect(contato.reload).to have_attributes(contact_type: 'customer', customer_since: desde + 1.day)
    end

    it 'não mexe em quem já não é cliente, e nem chama o bloco' do
      contato = create(:contact, account: account, phone_number: '+5511987650001')

      expect(contato.revert_customer!(to: 'lead') { raise 'o bloco não devia rodar' }).to be(false)
      expect(contato.reload.contact_type).to eq('lead')
    end

    it 'só aceita voltar para visitante ou lead' do
      contato = cliente(phone_number: '+5511987650001')

      expect(['customer', nil, 'outro'].map { |tipo| contato.revert_customer!(to: tipo) { true } }).to eq([false, false, false])
      expect(contato.reload).to have_attributes(contact_type: 'customer', customer_since: desde)
    end

    it 'grava mesmo com dado antigo fora do formato' do
      contato = cliente
      contato.update_columns(phone_number: '11 98765-0001') # rubocop:disable Rails/SkipsModelValidations

      expect(contato.revert_customer!(to: 'lead') { true }).to be(true)
      expect(contato.reload).to have_attributes(contact_type: 'lead', customer_since: nil, phone_number: '11 98765-0001')
    end
  end

  # Cliente desde quando (E4, #2897): quem promove sabendo a data passa `since:`, e a mais antiga vence.
  describe '#become_customer!' do
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
end
