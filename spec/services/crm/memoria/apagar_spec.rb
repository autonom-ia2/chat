require 'rails_helper'

RSpec.describe Crm::Memoria::Apagar do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, name: 'Ana') }

  before { ligar_memoria!(account) }

  it 'invariante 13: apagar o contato deixa 0 linhas de autoria, de tarefa de memória e de bilhete dele' do
    message = mensagem!(conversation, :incoming, content: 'meu CPF é 123')
    Crm::Memoria::Origem.gravar!(message)
    passagem = Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')
    Crm::Memoria::PassagemJob.perform_now(passagem.id)
    expect(passagem.reload.bilhete).to be_present
    expect(Crm::Memoria::Compromissos.da_conversa(conversation)).to exist

    contact.destroy!

    expect(Crm::MensagemOrigem.where(contact_id: contact.id)).to be_empty
    expect(Crm::FollowUp.where(contact_id: contact.id)).to be_empty
    expect(passagem.reload).to have_attributes(bilhete: nil, bilhete_status: 'apagado')
    Crm::Memoria::ConciliacaoJob.perform_now
    expect(passagem.reload.bilhete).to be_nil
  end

  it 'o "quer" da IA que chega depois de o contato ser apagado não regrava o bilhete' do
    passagem = Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')
    Crm::Memoria::Bilhete.fallback!(passagem)
    Crm::Memoria::Bilhete.reservar!(passagem)
    cliente_ia = instance_double(Crm::Ai::ResponsesClient)
    allow(Crm::Memoria::Bilhete).to receive(:cliente).and_return(cliente_ia)
    allow(cliente_ia).to receive(:create) do
      described_class.contato!(contact)
      { text: { quer: 'Cotar seguro' }.to_json }
    end

    Crm::Memoria::Bilhete.melhorar!(passagem.reload)

    expect(passagem.reload).to have_attributes(bilhete: nil, bilhete_status: 'apagado')
  end

  it 'a varredura diária apaga o bilhete cuja conversa ficou sem contato' do
    passagem = Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')
    Crm::Memoria::Bilhete.fallback!(passagem)
    Contact.where(id: contact.id).delete_all

    expect { Crm::Memoria::VarreduraJob.perform_now }.to change { passagem.reload.bilhete }.to(nil)
  end
end
