require 'rails_helper'

RSpec.describe Autonomia::ContatoPeloEmailListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:contact) { create(:contact, account: account, email: 'ana@cliente.com.br') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, message_type: :incoming,
                     content_type: 'incoming_email')
  end

  def criada(alvo = message)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: alvo))
  end

  it 'está registrado no AsyncDispatcher' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end

  it 'sem a flag não enfileira nada' do
    expect { criada }.not_to have_enqueued_job(Autonomia::ContatoPeloEmailJob)
  end

  context 'with the flag on' do
    before { account.enable_features!(Autonomia::ContatoPeloEmail::FLAG) }

    it 'e-mail recebido: enfileira; resposta nossa e nota privada: nada' do
      expect { criada }.to have_enqueued_job(Autonomia::ContatoPeloEmailJob).with(message.id)

      nossa = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
      nota = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, private: true)
      expect { criada(nossa) }.not_to have_enqueued_job(Autonomia::ContatoPeloEmailJob)
      expect { criada(nota) }.not_to have_enqueued_job(Autonomia::ContatoPeloEmailJob)
    end
  end
end
