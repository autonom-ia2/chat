require 'rails_helper'

RSpec.describe Crm::MemoriaListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: conversation.inbox) }

  def evento(nome, **dados)
    Events::Base.new(nome, Time.zone.now, { message: message }.merge(dados))
  end

  it 'sem a flag não enfileira nada' do
    allow(Crm::Config).to receive(:enabled?).and_return(true)

    expect { listener.message_created(evento('message.created')) }.not_to have_enqueued_job(Crm::Memoria::OrigemJob)
  end

  context 'with the flag on' do
    before { ligar_memoria!(account) }

    it 'mensagem nova enfileira a autoria' do
      expect { listener.message_created(evento('message.created')) }.to have_enqueued_job(Crm::Memoria::OrigemJob).with(message.id)
    end

    it 'mensagem mudada: só o que muda autoria ou entrega; o recibo de lido não' do
      expect { listener.message_updated(evento('message.updated', previous_changes: { 'status' => %w[sent read] })) }
        .not_to have_enqueued_job(Crm::Memoria::OrigemJob)
      expect { listener.message_updated(evento('message.updated', previous_changes: { 'status' => %w[sent failed] })) }
        .to have_enqueued_job(Crm::Memoria::OrigemJob)
      expect { listener.message_updated(evento('message.updated', previous_changes: { private: [true, false] })) }
        .to have_enqueued_job(Crm::Memoria::OrigemJob)
    end

    it 'mudança só "de pele" nas marcas do canal (reação, voto escondido) não enfileira; apagar a mensagem enfileira' do
      pele = { 'content_attributes' => ['{"reactions":[]}', '{"reactions":[{"e":"x"}],"c2y_hidden":true}'] }
      apagada = { 'content_attributes' => [{}, { 'deleted' => true }] }

      expect { listener.message_updated(evento('message.updated', previous_changes: pele)) }.not_to have_enqueued_job(Crm::Memoria::OrigemJob)
      expect { listener.message_updated(evento('message.updated', previous_changes: apagada)) }.to have_enqueued_job(Crm::Memoria::OrigemJob)
    end
  end
end
