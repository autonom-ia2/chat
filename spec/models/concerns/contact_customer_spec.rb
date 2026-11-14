require 'rails_helper'

# #2896 (fatia 3) — o Desfazer de "Trazer minha lista" devolve ao tipo de antes quem a lista marcou como cliente
# (Contact#revert_customer!). Marcar e desmarcar pelo painel: customers_controller_spec.rb.
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
end
