require 'rails_helper'

RSpec.describe Crm::Memoria::ConciliacaoJob do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, name: 'Ana') }

  before { ligar_memoria!(account) }

  it 'recria a tarefa e o bilhete que o evento não fez, uma vez, e avisa o rastreador' do
    passagem = Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original

    described_class.perform_now
    described_class.perform_now

    expect(Crm::Memoria::Compromissos.da_conversa(conversation).count).to eq(1)
    expect(passagem.reload.bilhete).to be_present
    expect(ChatwootExceptionTracker).to have_received(:new).once
  end

  it 'não recria a tarefa quando a pessoa já respondeu depois da passagem' do
    Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')
    resposta = mensagem!(conversation, :outgoing, sender: ana, content: 'Oi!')
    Crm::Memoria::Origem.gravar!(resposta)

    described_class.perform_now

    expect(Crm::Memoria::Compromissos.da_conversa(conversation)).to be_empty
  end

  it 'duas passagens nas últimas 24 h e uma tarefa: o dono não vai e volta a cada ciclo' do
    bruno = create(:user, account: account, name: 'Bruno')
    primeira = Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')
    Crm::Memoria::PassagemJob.perform_now(primeira.id)
    segunda = Crm::Passagens.registrar!(conversation: conversation, de: porta, para: bruno, pedida_por: nil, motivo: 'passar_para')
    Crm::Memoria::PassagemJob.perform_now(segunda.id)
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original

    3.times { described_class.perform_now }

    tarefa = Crm::Memoria::Compromissos.da_conversa(conversation).sole
    expect(tarefa.recipient_user_ids).to eq([bruno.id])
    expect(tarefa.metadata.dig('memoria', 'passagem_ids')).to eq([primeira.id, segunda.id])
    expect(ChatwootExceptionTracker).not_to have_received(:new)
  end

  it 'reserva da IA esquecida e sem tentativa sobrando volta ao bilhete do código, sem alerta' do
    passagem = Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')
    Crm::Memoria::PassagemJob.perform_now(passagem.id)
    passagem.update_columns(bilhete_status: 'gerando', bilhete_reservado_em: 20.minutes.ago, bilhete_tentativas: 2) # rubocop:disable Rails/SkipsModelValidations
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original

    described_class.perform_now

    expect(passagem.reload.bilhete_status).to eq('fallback')
    expect(ChatwootExceptionTracker).not_to have_received(:new)
  end

  it 'conta sem a flag fica de fora' do
    account.disable_features!(Crm::Memoria::FLAG)
    Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')

    described_class.perform_now

    expect(Crm::Memoria::Compromissos.da_conversa(conversation)).to be_empty
  end
end
