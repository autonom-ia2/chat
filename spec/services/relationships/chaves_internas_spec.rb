require 'rails_helper'

# #3176 — a lista central das chaves internas do contato.
RSpec.describe Relationships::ChavesInternas do
  # MOTIVO: a lista junta as três da WAHA e o controle da Prospecção, pelas constantes de quem grava (mudou lá, muda aqui).
  it 'é a WAHA mais o controle da Prospecção, e só isso', :aggregate_failures do
    expect(described_class::LISTA).to match_array(
      %w[waha_whatsapp_chat_id waha_whatsapp_jid waha_whatsapp_lid
         autonomia_prospecting_lead_id autonomia_prospecting_provider autonomia_prospecting_provider_place_id
         autonomia_prospecting_converted_by_id autonomia_prospecting_contact_name autonomia_prospecting_contact_job_title]
    )
    expect(described_class::LISTA).to include(*Waha::ContactChatId::KEYS)
    expect(described_class::LISTA).to be_frozen
  end

  # MOTIVO: a nota e as avaliações no Google servem à equipe; o cargo é da pessoa.
  it 'não esconde o que serve à equipe' do
    %w[autonomia_prospecting_rating autonomia_prospecting_reviews_count job_title cpf].each do |chave|
      expect(described_class.interna?(chave)).to be(false), chave
    end
  end

  # MOTIVO: compara a chave inteira; parecida, símbolo e nil não confundem.
  it 'compara a chave inteira', :aggregate_failures do
    expect(described_class.interna?('waha_whatsapp_jid')).to be(true)
    expect(described_class.interna?(:autonomia_prospecting_lead_id)).to be(true)
    expect(described_class.interna?('waha_whatsapp_outra')).to be(false)
    expect(described_class.interna?('autonomia_prospecting_lead')).to be(false)
    expect(described_class.interna?(nil)).to be(false)
  end

  # MOTIVO: tira só as internas e não muda o que recebeu.
  it 'sem_internas devolve uma cópia sem as internas' do
    atributos = { 'waha_whatsapp_chat_id' => '5511900000000@c.us', 'autonomia_prospecting_lead_id' => 7,
                  'autonomia_prospecting_rating' => 4.5, 'placa' => 'ABC1D23' }

    expect(described_class.sem_internas(atributos)).to eq('autonomia_prospecting_rating' => 4.5, 'placa' => 'ABC1D23')
    expect(atributos.keys.size).to eq(4)
    expect(described_class.sem_internas(nil)).to eq({})
  end
end
