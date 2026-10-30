require 'rails_helper'

# #2246: a marca de "o sistema já marcou como lidas até aqui" cobre a mensagem marcada e as anteriores, e só anda para a
# frente.
RSpec.describe ConversaCanal::LeituraDoSistema do
  let(:conversation) { create(:conversation) }
  let(:inicio) { Time.zone.parse('2026-10-27 10:00:00.123456') }

  def mensagem(segundos)
    travel_to(inicio + segundos) { create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox) }
  end

  before { conversation.account.enable_features!(ConversaCanal::VistaNoCelular::FLAG) }

  after { Redis::Alfred.delete(described_class.chave(conversation)) }

  it 'cobre a mensagem marcada e as anteriores, não as que chegaram depois' do
    antes = mensagem(0)
    marcada = mensagem(1)
    depois = mensagem(2)

    described_class.registrar(conversation, ate: marcada.created_at)

    expect(described_class.cobre?(antes)).to be(true)
    expect(described_class.cobre?(marcada.reload)).to be(true)
    expect(described_class.cobre?(depois)).to be(false)
  end

  it 'não cobre nada sem marca' do
    expect(described_class.cobre?(mensagem(0))).to be(false)
  end

  it 'só anda para a frente: uma marca mais antiga não encolhe a cobertura' do
    described_class.registrar(conversation, ate: inicio + 5.seconds)
    described_class.registrar(conversation, ate: inicio)

    expect(described_class.ate(conversation)).to eq(inicio + 5.seconds)
  end

  it 'não grava nada com a flag desligada' do
    conversation.account.disable_features!(ConversaCanal::VistaNoCelular::FLAG)
    expect(Redis::Alfred).not_to receive(:with)

    described_class.registrar(conversation, ate: inicio)

    expect(described_class.ate(conversation)).to be_nil
  end

  it 'nunca levanta ao gravar: a leitura ao canal e o "digitando" seguem' do
    allow(Redis::Alfred).to receive(:with).and_raise(ConnectionPool::TimeoutError)

    expect { described_class.registrar(conversation, ate: inicio) }.not_to raise_error
  end

  it 'descarta a leitura quando o Redis falha (erra para "não lida")' do
    lida = mensagem(0)
    allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError)

    expect(described_class.cobre?(lida)).to be(true)
  end
end
