require 'rails_helper'

# #1938, parte B: o job da cópia no Enviados e o gancho depois do envio por SMTP.
RSpec.describe ConversaCanal::CopiaNoEnviadosJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account, imap_enabled: true, smtp_enabled: true) }
  let(:conversa) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:mensagem) do
    create(:message, conversation: conversa, account: account, inbox: channel.inbox, message_type: :outgoing,
                     source_id: 'conversation/abc/messages/1@exemplo.test')
  end
  let(:copia) { instance_double(ConversaCanal::CopiaNoEnviados, gravar: :gravada) }

  before do
    account.enable_features!('email_enviados')
    allow(ConversaCanal::CopiaNoEnviados).to receive(:new).and_return(copia)
  end

  it 'agenda com espera e grava' do
    expect { described_class.agendar(mensagem) }.to have_enqueued_job(described_class).with(mensagem)

    perform_enqueued_jobs

    expect(copia).to have_received(:gravar)
  end

  it 'sem a chave email_enviados não agenda' do
    account.disable_features!('email_enviados')

    expect { described_class.agendar(mensagem) }.not_to have_enqueued_job(described_class)
  end

  it 'caixa ocupada pela importação: volta depois, até o teto', :aggregate_failures do
    allow(copia).to receive(:gravar).and_raise(MutexApplicationJob::LockAcquisitionError, 'caixa ocupada')

    expect { described_class.perform_now(mensagem) }.to have_enqueued_job(described_class).with(mensagem, 1)
    expect { described_class.perform_now(mensagem, described_class::VOLTAS) }.not_to have_enqueued_job(described_class)
  end

  it 'credencial recusada: desiste sem tentar de novo' do
    allow(copia).to receive(:gravar).and_raise(ConversaCanal::ConexaoDoEmail::CredencialRecusada, 'reauthorization_required')

    expect { described_class.perform_now(mensagem) }.not_to have_enqueued_job(described_class)
  end

  describe 'depois do envio por SMTP' do
    let(:entrega) { instance_double(Mail::Message, message_id: 'conversation/abc/messages/9@exemplo.test') }

    before do
      mailer = instance_double(ActionMailer::MessageDelivery, deliver_now: entrega)
      allow(ConversationReplyMailer).to receive(:with).and_return(double(email_reply: mailer)) # rubocop:disable RSpec/VerifiedDoubles
    end

    it 'agenda a cópia da mensagem enviada' do
      mensagem.update!(source_id: nil)
      allow(described_class).to receive(:agendar)

      Email::SendOnEmailService.new(message: mensagem).perform

      expect(described_class).to have_received(:agendar).with(have_attributes(id: mensagem.id, source_id: entrega.message_id))
    end
  end
end
