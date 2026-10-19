require 'rails_helper'

# #1865 — a mensagem com trabalho antes do envio (salvar contato, marcar como lida) segura a conversa até sair; a
# seguinte da mesma conversa espera, para não passar na frente.
describe ConversaCanal::EnvioEmOrdem do
  let(:conversation) { create(:conversation) }
  let(:chave) { "conversa_canal:envio_em_ordem:#{conversation.id}" }

  before do
    Redis::Alfred.delete(chave)
    allow(Rails.logger).to receive(:info)
  end

  after { Redis::Alfred.delete(chave) }

  it 'sem trabalho e sem ninguém na frente, segue na hora sem travar' do
    allow(Kernel).to receive(:sleep)
    durante = nil

    described_class.executar(conversation, -> { false }) { durante = Redis::Alfred.exists?(chave) }

    expect(durante).to be(false)
    expect(Kernel).not_to have_received(:sleep)
  end

  it 'com trabalho, segura a conversa durante o trabalho e o envio e solta no fim' do
    durante = nil

    described_class.executar(conversation, -> { true }) { durante = Redis::Alfred.exists?(chave) }

    expect(durante).to be(true)
    expect(Redis::Alfred.exists?(chave)).to be(false)
  end

  it 'a mensagem seguinte espera a da frente terminar antes de sair' do
    Redis::Alfred.set(chave, 'da-frente', nx: true, ex: 60)
    ordem = []
    allow(Kernel).to receive(:sleep) do
      ordem << :frente_saiu
      Redis::Alfred.delete(chave)
    end

    described_class.executar(conversation, -> { false }) { ordem << :seguinte_saiu }

    expect(ordem).to eq(%i[frente_saiu seguinte_saiu])
  end

  it 'não solta a trava de outra mensagem' do
    described_class.executar(conversation, -> { true }) do
      Redis::Alfred.delete(chave)
      Redis::Alfred.set(chave, 'outra', nx: true, ex: 60)
    end

    expect(Redis::Alfred.get(chave)).to eq('outra')
  end

  it 'Redis fora do ar não impede o envio' do
    allow(Redis::Alfred).to receive(:exists?).and_raise(Redis::CannotConnectError)
    allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError)
    saiu = false

    described_class.executar(conversation, -> { true }) { saiu = true }

    expect(saiu).to be(true)
  end
end
