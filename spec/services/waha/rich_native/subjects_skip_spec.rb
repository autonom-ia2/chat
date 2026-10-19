require 'rails_helper'
require_relative 'inbound_context'

# chat#1709 (rodada de correção, item 16): a bolha "abra no celular" e o aviso de visualização única não pedem a IA de
# assunto (Crm::Subjects.identificar_depois), com a flag. Sem a flag, ou numa mensagem real, como na main.
describe Waha::RichNative::SubjectsSkip do
  include_context 'with a waha inbox and its connector'

  before { allow(Crm::Subjects).to receive_messages(ligado?: true, ordem_do_turno?: false) }

  def incoming(attributes)
    message = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'x')
    message.update_column(:content_attributes, attributes) # rubocop:disable Rails/SkipsModelValidations
    message.reload
  end

  it 'skips the unsupported bubble and the view once notice with the flag' do
    flag_on!

    expect { Crm::Subjects.identificar_depois(incoming('is_unsupported' => true)) }.not_to have_enqueued_job(Crm::Subjects::IdentifyJob)
    expect { Crm::Subjects.identificar_depois(incoming('view_once_unavailable' => true)) }.not_to have_enqueued_job(Crm::Subjects::IdentifyJob)
  end

  it 'still identifies a real message with the flag' do
    flag_on!

    expect { Crm::Subjects.identificar_depois(incoming({})) }.to have_enqueued_job(Crm::Subjects::IdentifyJob)
  end

  it 'identifies the bubble as in main without the flag' do
    expect { Crm::Subjects.identificar_depois(incoming('is_unsupported' => true)) }.to have_enqueued_job(Crm::Subjects::IdentifyJob)
  end
end
