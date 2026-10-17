require 'rails_helper'

# #1702 — a lida no WhatsApp sai do request, na fila low, com debounce por conversa.
describe ConversaCanal::LeituraNoCanalJob do
  let(:conversation) { create(:conversation) }
  let(:chave) { "conversa_canal:leitura:#{conversation.id}" }

  before { Redis::Alfred.delete(chave) }
  after { Redis::Alfred.delete(chave) }

  it 'agenda na fila low para o fim da espera' do
    freeze_time do
      described_class.agendar(conversation)

      expect(described_class).to have_been_enqueued.with(conversation).on_queue('low').at(described_class::ESPERA.from_now)
    end
  end

  it 'várias aberturas na mesma espera viram um job só' do
    3.times { described_class.agendar(conversation) }

    expect(described_class).to have_been_enqueued.with(conversation).once
  end

  it 'outra conversa não é segurada pelo debounce desta' do
    outra = create(:conversation)
    Redis::Alfred.delete("conversa_canal:leitura:#{outra.id}")

    described_class.agendar(conversation)
    described_class.agendar(outra)

    expect(described_class).to have_been_enqueued.twice
  end

  it 'perform entrega ao serviço da conversa' do
    servico = instance_double(ConversaCanal::LeituraNoCanal, perform: nil)
    allow(ConversaCanal::LeituraNoCanal).to receive(:new).with(conversation: conversation).and_return(servico)

    described_class.perform_now(conversation)

    expect(servico).to have_received(:perform)
  end
end
