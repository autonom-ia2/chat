require 'rails_helper'

# #1938, parte B: a cópia do e-mail enviado pelo painel na pasta de enviados da conta do cliente.
RSpec.describe ConversaCanal::CopiaNoEnviados do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_email, account: account, imap_enabled: true, imap_address: 'imap.exemplo.test', imap_login: 'caixa@exemplo.test',
                           smtp_enabled: true, smtp_address: 'smtp.exemplo.test', email: 'caixa@exemplo.test')
  end
  let(:contato) { create(:contact, account: account, email: 'cliente@cliente.test') }
  let(:conversa) { create(:conversation, account: account, inbox: channel.inbox, contact: contato) }
  let(:mensagem) do
    create(:message, conversation: conversa, account: account, inbox: channel.inbox, message_type: :outgoing,
                     content: 'Segue a proposta.', source_id: 'conversation/abc/messages/1@exemplo.test')
  end
  let(:imap) { instance_double(Net::IMAP) }
  let(:lock) { instance_double(ConversaCanal::LockDaCaixa, renovar!: true) }
  let(:pastas) do
    [Net::IMAP::MailboxList.new([:HasNoChildren], '/', 'INBOX'),
     Net::IMAP::MailboxList.new(%i[HasNoChildren Sent], '/', 'Itens Enviados')]
  end

  before do
    account.enable_features!('email_enviados')
    allow(ConversaCanal::ConexaoDoEmail).to receive(:abrir).with(channel).and_yield(imap, lock)
    allow(imap).to receive(:list).with('', '*').and_return(pastas)
    allow(imap).to receive(:examine)
    allow(imap).to receive(:append)
  end

  describe '.aplica?' do
    it 'caixa com IMAP que envia por SMTP, com a chave e já enviada' do
      expect(described_class.aplica?(mensagem)).to be(true)
    end

    it 'não sem a chave email_enviados, sem IMAP, na Microsoft, sem envio ou com falha', :aggregate_failures do
      account.disable_features!('email_enviados')
      expect(described_class.aplica?(mensagem)).to be(false)
      account.enable_features!('email_enviados')

      expect(described_class.aplica?(mensagem.tap { |m| m.source_id = nil })).to be(false)
      mensagem.source_id = 'x@y'
      expect(described_class.aplica?(mensagem.tap { |m| m.status = :failed })).to be(false)
      mensagem.status = :sent

      channel.update!(provider: 'microsoft')
      expect(described_class.aplica?(mensagem.reload)).to be(false)
      channel.update!(provider: nil, imap_enabled: false)
      expect(described_class.aplica?(mensagem.reload)).to be(false)
    end
  end

  it 'grava na pasta marcada \\Sent, já lida, com o Message-ID do envio', :aggregate_failures do
    allow(imap).to receive(:uid_search).and_return([])

    expect(described_class.new(mensagem).gravar).to eq(:gravada)

    expect(imap).to have_received(:examine).with('Itens Enviados')
    expect(imap).to have_received(:uid_search).with(['HEADER', 'Message-ID', mensagem.source_id])
    expect(imap).to have_received(:append) do |pasta, cru, flags, data|
      expect(pasta).to eq('Itens Enviados')
      expect(flags).to eq([:Seen])
      expect(data).to eq(mensagem.created_at)
      email = Mail.new(cru)
      expect(email.message_id).to eq(mensagem.source_id)
      expect(email.date.to_i).to eq(mensagem.created_at.to_i)
      expect(email.to).to eq(['cliente@cliente.test'])
      expect(cru).to include('Segue a proposta.')
    end
  end

  it 'o provedor já guardou (Gmail, Outlook): não grava de novo' do
    allow(imap).to receive(:uid_search).and_return([42])

    expect(described_class.new(mensagem).gravar).to eq(:ja_estava)
    expect(imap).not_to have_received(:append)
  end

  it 'servidor sem pasta marcada \\Sent: não chuta o nome e não grava' do
    allow(imap).to receive(:list).and_return([Net::IMAP::MailboxList.new([], '/', 'INBOX'),
                                              Net::IMAP::MailboxList.new([], '/', 'Sent')])

    expect(described_class.new(mensagem).gravar).to eq(:sem_pasta)
    expect(imap).not_to have_received(:append)
  end
end
