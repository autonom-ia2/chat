require 'rails_helper'

RSpec.describe Crm::Memoria::Bilhete do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, name: 'Ana') }
  let(:cliente_ia) { instance_double(Crm::Ai::ResponsesClient) }

  before do
    ligar_memoria!(account)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    credencial = instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: 'chave')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(credencial)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente_ia)
  end

  def passar
    Crm::Passagens.registrar!(conversation: conversation, de: porta, para: ana, pedida_por: nil, motivo: 'passar_para')
  end

  it 'o código monta o bilhete na hora: falas literais do cliente desde a passagem anterior, sem duplicata nem indisponível' do
    mensagem!(conversation, :incoming, content: 'Quero cotar o seguro do meu carro', created_at: 3.minutes.ago)
    mensagem!(conversation, :incoming, content: 'This message is unavailable', created_at: 2.minutes.ago)
    mensagem!(conversation, :outgoing, sender: porta, content: 'Qual a placa?', created_at: 90.seconds.ago)
    mensagem!(conversation, :incoming, content: 'ABC1D23', created_at: 1.minute.ago)
    passagem = passar
    described_class.fallback!(passagem)

    bilhete = passagem.reload.bilhete
    expect(passagem.bilhete_status).to eq('fallback')
    expect(bilhete['fala_cliente'].pluck('texto')).to eq(['Quero cotar o seguro do meu carro', 'ABC1D23'])
    expect(bilhete).to include('fonte' => 'codigo', 'quer' => nil, 'motivo' => 'passar_para')
  end

  it 'a IA melhora o "quer" numa chamada só; o retry depois de pronto não chama de novo (invariante 11)' do
    mensagem!(conversation, :incoming, content: 'Quero cotar o seguro do meu carro')
    passagem = passar
    described_class.fallback!(passagem)
    allow(cliente_ia).to receive(:create).and_return(text: { quer: 'Cotar seguro auto' }.to_json)

    2.times { Crm::Memoria::BilheteJob.perform_now(passagem.id) }

    expect(cliente_ia).to have_received(:create).once
    expect(passagem.reload).to have_attributes(bilhete_status: 'pronto', bilhete_tentativas: 1)
    expect(passagem.bilhete).to include('quer' => 'Cotar seguro auto', 'fonte' => 'ia')
  end

  it 'invariante 14: a IA falha duas vezes e a passagem fica com o bilhete do código (fallback)' do
    passagem = passar
    described_class.fallback!(passagem)
    allow(cliente_ia).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'fora')

    3.times { Crm::Memoria::BilheteJob.perform_now(passagem.id) }

    expect(cliente_ia).to have_received(:create).twice
    expect(passagem.reload).to have_attributes(bilhete_status: 'fallback', bilhete_tentativas: 2)
    expect(passagem.bilhete['fonte']).to eq('codigo')
  end

  it 'reserva esquecida em "gerando" só é retomada depois de 10 min' do
    passagem = passar
    described_class.fallback!(passagem)
    passagem.update_columns(bilhete_status: 'gerando', bilhete_reservado_em: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.reservar!(passagem)).to be(false)
    passagem.update_columns(bilhete_reservado_em: 11.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.reservar!(passagem)).to be(true)
  end

  it 'a passagem gravada enfileira o bilhete (com a flag) pelo after_commit' do
    expect { passar }.to have_enqueued_job(Crm::Memoria::PassagemJob)
  end
end
