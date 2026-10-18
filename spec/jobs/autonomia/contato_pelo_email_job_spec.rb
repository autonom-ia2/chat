require 'rails_helper'

RSpec.describe Autonomia::ContatoPeloEmailJob do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:contact) { create(:contact, account: account, name: 'ana@cliente.com.br', email: 'ana@cliente.com.br') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:corpo) { "Bom dia, quero falar com vocês.\n\nAna Prado\n(11) 98765-4321" }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

  def email(**atributos)
    create(:message, { account: account, inbox: inbox, conversation: conversation, sender: contact, message_type: :incoming,
                       content_type: 'incoming_email', content: corpo,
                       content_attributes: { email: { from: ['ana@cliente.com.br'], text_content: { reply: corpo } } } }.merge(atributos))
  end

  before do
    Redis::Alfred.scan_each(match: "#{Autonomia::ContatoPeloEmail::Freios::PREFIXO}:*") { |key| Redis::Alfred.delete(key) }
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create).and_return(text: { tipo: 'pessoa', nome: 'Ana Prado', email: nil, telefone: '(11) 98765-4321' }.to_json)
  end

  it 'conta sem a flag: nem chama a IA', :aggregate_failures do
    described_class.perform_now(email.id)

    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    expect(contact.reload.name).to eq('ana@cliente.com.br')
  end

  context 'with the flag on' do
    before { account.enable_features!(Autonomia::ContatoPeloEmail::FLAG) }

    it 'e-mail recebido de pessoa: completa nome e telefone' do
      described_class.perform_now(email.id)

      expect(contact.reload).to have_attributes(name: 'Ana Prado', phone_number: '+5511987654321')
    end

    it 'mensagem outgoing e nota privada: ignoradas', :aggregate_failures do
      described_class.perform_now(email(message_type: :outgoing, sender: nil).id)
      described_class.perform_now(email(message_type: :outgoing, private: true, sender: nil).id)
      described_class.perform_now(email(private: true).id)

      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(contact.reload.name).to eq('ana@cliente.com.br')
    end

    it 'resposta automática marcada no cabeçalho e caixa que não é de e-mail: ignoradas' do
      automatica = email(content_attributes: { email: { auto_reply: true, from: ['ana@cliente.com.br'], text_content: { reply: corpo } } })
      outra_caixa = create(:inbox, account: account)
      whatsapp = create(:message, account: account, inbox: outra_caixa, sender: contact, message_type: :incoming,
                                  conversation: create(:conversation, account: account, inbox: outra_caixa, contact: contact))

      described_class.perform_now(automatica.id)
      described_class.perform_now(whatsapp.id)

      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'mensagem que não existe mais: nada' do
      expect { described_class.perform_now(0) }.not_to raise_error
    end

    # Pega: o erro voltar ao Sidekiq (mais 3 tentativas do config/sidekiq.yml) em vez de parar em 2 novas tentativas.
    it 'erro antes da leitura: no máximo 2 novas tentativas, e desiste registrando só a classe', :aggregate_failures do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_raise(ActiveRecord::Deadlocked)
      allow(Rails.logger).to receive(:error)
      mensagem = email

      expect { perform_enqueued_jobs { described_class.perform_later(mensagem.id) } }.not_to raise_error

      expect(Crm::Ai::CredentialResolver).to have_received(:new).exactly(3).times
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(Rails.logger).to have_received(:error).with(include('desistiu', 'erro=ActiveRecord::Deadlocked')).once
    end

    # Pega: a nova tentativa pagar a IA de novo pelo mesmo e-mail.
    it 'erro depois da leitura: a nova tentativa não chama a IA de novo', :aggregate_failures do
      allow(Autonomia::Decisores::Aplicador).to receive(:new).and_raise(ActiveRecord::Deadlocked)
      mensagem = email

      expect { perform_enqueued_jobs { described_class.perform_later(mensagem.id) } }.not_to raise_error

      expect(Crm::Ai::CredentialResolver).to have_received(:new).twice
      expect(cliente).to have_received(:create).once
    end
  end
end
