require 'rails_helper'

RSpec.describe TemplateFields::ContactResolver do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, account: account, name: 'ana Souza', email: 'ana@exemplo.com.br', phone_number: '+5511987654321',
                     additional_attributes: { 'company_name' => 'Padaria Sol' })
  end

  def value(key, person = contact)
    described_class.new(person).value(key)
  end

  it 'reads the customer fields' do
    expect(value('cliente.nome')).to eq('ana Souza')
    expect(value('cliente.email')).to eq('ana@exemplo.com.br')
    expect(value('cliente.telefone')).to eq('(11) 98765-4321')
    expect(value('empresa_cliente.nome')).to eq('Padaria Sol')
    expect(value('empresa_cliente.cnpj')).to be_nil
  end

  it 'has one first name rule, the scheduling one' do
    expect(value('cliente.primeiro_nome')).to eq(Crm::BookingV2::InviteText.first_name(contact))
    expect(value('cliente.primeiro_nome')).to eq('ana')
    named_by_phone = create(:contact, account: account, name: '+55 11 98765-4322')
    expect(value('cliente.primeiro_nome', named_by_phone)).to be_nil
  end

  it 'writes a number of another country in the international format' do
    foreign = create(:contact, account: account, phone_number: '+12025550123')

    expect(value('cliente.telefone', foreign)).to eq('+1 202-555-0123')
  end

  it 'has no mobile for a contact without phone' do
    expect(value('cliente.telefone', create(:contact, account: account, phone_number: nil))).to be_nil
  end

  it 'gives the customer date only to a customer, in the account time zone' do
    expect(value('cliente.cliente_desde')).to be_nil

    contact.update!(contact_type: :customer, customer_since: Time.utc(2026, 3, 1, 2, 0))
    expect(value('cliente.cliente_desde')).to eq('28/02/2026')
  end

  it 'prefers the company record over the copied name' do
    company = create(:company, account: account, name: 'Sol Ltda', additional_attributes: { 'cnpj' => '12.345.678/0001-90' })
    contact.update!(company: company)

    expect(value('empresa_cliente.nome')).to eq('Sol Ltda')
    expect(value('empresa_cliente.cnpj')).to eq('12.345.678/0001-90')
  end

  it 'answers nothing for a key of another resolver' do
    expect(value('negocio.valor')).to be_nil
  end
end
