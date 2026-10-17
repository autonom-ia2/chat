require 'rails_helper'

RSpec.describe Crm::MemoriaListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming) }

  def mudou(mudancas, alvo = message)
    listener.message_updated(Events::Base.new('message.updated', Time.zone.now, message: alvo, previous_changes: mudancas))
  end

  it 'sem a flag não enfileira nada' do
    allow(Crm::Config).to receive(:enabled?).and_return(true)

    expect { mudou('content' => %w[2002 2022]) }.not_to have_enqueued_job(Crm::Memoria::MensagemJob)
  end

  context 'with the flag on' do
    before { ligar_memoria!(account) }

    it 'o cliente editou o texto: "editada"; apagada: "apagada"; recibo, reação e mensagem nossa: nada' do
      expect { mudou('content' => %w[2002 2022]) }.to have_enqueued_job(Crm::Memoria::MensagemJob).with(message.id, 'editada')

      expect { mudou('status' => %w[sent read]) }.not_to have_enqueued_job(Crm::Memoria::MensagemJob)
      nossa = create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :outgoing)
      expect { mudou({ 'content' => %w[a b] }, nossa) }.not_to have_enqueued_job(Crm::Memoria::MensagemJob)

      message.update_columns(content_attributes: { deleted: true }) # rubocop:disable Rails/SkipsModelValidations
      expect { mudou('content_attributes' => [{}, { 'deleted' => true }]) }
        .to have_enqueued_job(Crm::Memoria::MensagemJob).with(message.id, 'apagada')
    end
  end
end
