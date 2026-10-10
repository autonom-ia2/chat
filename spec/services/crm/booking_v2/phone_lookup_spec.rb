require 'rails_helper'

RSpec.describe Crm::BookingV2::PhoneLookup do
  let(:account) { create(:account) }

  describe '.normalize' do
    it 'lê número brasileiro sem + no país padrão e devolve E.164' do
      expect(described_class.normalize('(11) 91234-5678')).to eq('+5511912345678')
      expect(described_class.normalize(' 11 91234 5678 ', region: :br)).to eq('+5511912345678')
    end

    it 'aceita número com + de outro país sem depender da região' do
      expect(described_class.normalize('+1 415 555 2671')).to eq('+14155552671')
      expect(described_class.normalize('+55 11 91234-5678', region: :us)).to eq('+5511912345678')
    end

    it 'recusa texto, número curto, vazio e entrada longa demais' do
      expect(described_class.normalize('abc')).to be_nil
      expect(described_class.normalize('11 9123')).to be_nil
      expect(described_class.normalize('')).to be_nil
      expect(described_class.normalize(nil)).to be_nil
      expect(described_class.normalize("11912345678#{'9' * 40}")).to be_nil
    end
  end

  describe '.region_for' do
    it 'deduz o país do fuso e cai no Brasil quando não acha' do
      expect(described_class.region_for('America/Sao_Paulo')).to eq(:br)
      expect(described_class.region_for('Europe/Lisbon')).to eq(:pt)
      expect(described_class.region_for('Brasilia')).to eq(:br)
      expect(described_class.region_for('Nowhere/Land')).to eq(:br)
    end
  end

  describe '.find_contact' do
    it 'acha o contato gravado sem o nono dígito a partir do número novo' do
      legacy = account.contacts.create!(name: 'Cliente Antigo', phone_number: '+551187654321')

      expect(described_class.find_contact(account: account, e164: '+5511987654321')).to eq(legacy)
    end

    it 'prefere a forma exata quando as duas existem' do
      account.contacts.create!(name: 'Legado', phone_number: '+551187654321')
      exact = account.contacts.create!(name: 'Exato', phone_number: '+5511987654321')

      expect(described_class.find_contact(account: account, e164: '+5511987654321')).to eq(exact)
    end

    it 'não confunde telefone fixo nem contato de outra conta' do
      account.contacts.create!(name: 'Fixo', phone_number: '+551132654321')
      create(:account).contacts.create!(name: 'Outra conta', phone_number: '+5511987654321')

      expect(described_class.find_contact(account: account, e164: '+5511932654321')).to be_nil
      expect(described_class.find_contact(account: account, e164: '+5511987654321')).to be_nil
    end

    it 'acha número estrangeiro só pela forma exata e não altera o contato' do
      contact = account.contacts.create!(name: 'Nome Original', phone_number: '+14155552671')

      expect(described_class.find_contact(account: account, e164: '+14155552671')).to eq(contact)
      expect(contact.reload.name).to eq('Nome Original')
    end
  end
end
