require 'rails_helper'
require 'timeout'

# #2143, com duas conexões reais: o DELETE do contato trava o contato antes de ler os leads, e os leads antes de decidir
# entre apagar e guardar a prova da recusa.
RSpec.describe Autonomia::Prospecting::LeadsDoContatoExcluido, :crm_travas, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account).tap { |conta| conta.enable_features!(:crm_arquivados) } }
  let!(:contact) { account.contacts.create!(name: 'Maria', phone_number: '+5511999992144') }
  let(:pronto) { Queue.new }
  let(:soltar) { Queue.new }
  let(:resultados) { Queue.new }

  after do
    soltar << true
    crm_travas_threads.each { |thread| thread.join(1) || thread.kill.join }
  ensure
    Autonomia::Prospecting::Lead.where(account_id: account.id).delete_all
    Contact.where(account_id: account.id).delete_all
    apagar_conta_gravada(account)
  end

  def create_lead(place, **attributes)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "places/#{place}",
                                         name: 'Clinica', phone: '+5511999992144', decision_name: 'Maria', **attributes)
  end

  # Outra conexão faz `antes` numa transação, avisa e segura as travas até `soltar`.
  def outro_processo(antes)
    aviso = pronto
    espera = soltar
    em_outra_conexao(resultados) do
      ActiveRecord::Base.transaction do
        antes.call
        aviso << true
        espera.pop
      end
      true
    end
    pronto.pop
  end

  def excluir_e_soltar
    esperar_na_trava(em_outra_conexao(resultados) { Contact.find(contact.id).destroy! && true })
    soltar << true
    crm_travas_threads.each(&:join)
  end

  it 'a conversão que liga o lead ao contato enquanto o DELETE esperava: o DELETE o lê depois e o apaga' do
    lead = create_lead('convertido')
    outro_processo(lambda do
      Contact.where(id: contact.id).lock.pluck(:id)
      Autonomia::Prospecting::Lead.where(id: lead.id).update_all(contact_id: contact.id) # rubocop:disable Rails/SkipsModelValidations
      Contact.where(id: contact.id).update_all(custom_attributes: { 'autonomia_prospecting_lead_id' => lead.id }) # rubocop:disable Rails/SkipsModelValidations
    end)

    excluir_e_soltar

    expect(resultados_de(resultados, 2)).to eq([true, true])
    expect(Autonomia::Prospecting::Lead.exists?(lead.id)).to be(false)
  end

  it 'a recusa gravada enquanto o DELETE esperava a trava do lead: o lead fica só com a prova, não é apagado' do
    lead = create_lead('recusa', contact: contact)
    Contact.where(id: contact.id).update_all(custom_attributes: { 'autonomia_prospecting_lead_id' => lead.id }) # rubocop:disable Rails/SkipsModelValidations
    outro_processo(lambda do
      Autonomia::Prospecting::Lead.where(id: lead.id).lock.pluck(:id)
      Autonomia::Prospecting::Lead.where(id: lead.id).update_all(consent_refused_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end)

    excluir_e_soltar

    expect(resultados_de(resultados, 2)).to eq([true, true])
    expect(lead.reload).to have_attributes(phone: '+5511999992144', decision_name: nil, contact_id: nil)
  end
end
