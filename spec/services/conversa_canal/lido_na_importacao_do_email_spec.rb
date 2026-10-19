require 'rails_helper'

# #1870 — a importação com o lido sincronizado: conexão que não vaza e falha do lido que não derruba o minuto.
RSpec.describe ConversaCanal::LidoNaImportacaoDoEmail do
  include ActionMailbox::TestHelper

  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :imap_email, account: account) }
  let(:imap) { instance_double(Net::IMAP) }
  let(:eml) { Rails.root.join('spec/fixtures/files/only_text.eml').read }
  let(:servico) { Imap::FetchEmailService.new(channel: channel) }
  let(:tracker) { instance_double(ChatwootExceptionTracker, capture_exception: true) }

  def recusa(texto)
    Net::IMAP::NoResponseError.new(Net::IMAP::TaggedResponse.new('A1', 'NO', Net::IMAP::ResponseText.new(nil, texto), ''))
  end

  before do
    account.enable_features!(ConversaCanal::EmailLido::FLAG)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(authenticate: nil, select: nil, logout: nil, disconnect: nil)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    Redis::Alfred.delete("conversa_canal:email_lido:falha_rastreada:#{channel.inbox.id}")
  end

  after { Redis::Alfred.delete("conversa_canal:email_lido:falha_rastreada:#{channel.inbox.id}") }

  it 'falha ao trazer o lido com o socket caído: os e-mails do minuto voltam e a conexão é fechada sem estourar' do
    travel_to '26.10.2020 10:00'.to_datetime do
      allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([1])
      allow(imap).to receive(:fetch).with([1], 'BODY.PEEK[HEADER]').and_return([Net::IMAP::FetchData.new(1, 'BODY[HEADER]' => eml)])
      allow(imap).to receive(:fetch).with(1, 'BODY.PEEK[]').and_return([Net::IMAP::FetchData.new(1, 'BODY[]' => eml)])
      allow(imap).to receive(:responses).with('UIDVALIDITY').and_yield([777])
      allow(imap).to receive(:search).with(%w[SINCE 24-Oct-2020]).and_raise(IOError, 'socket caiu')
      allow(imap).to receive(:logout).and_raise(IOError, 'socket caiu')

      emails = servico.perform

      expect(emails.length).to eq(1)
      expect(tracker).to have_received(:capture_exception).once
      # Ao rastreador vai só a classe, nunca o texto do provedor.
      expect(ChatwootExceptionTracker).to have_received(:new)
        .with(having_attributes(class: ConversaCanal::FalhaDoEmailLido, message: 'IOError'), account: account)
      expect(imap).to have_received(:disconnect)
    end
  end

  it 'autenticação recusada fecha o socket antes de relançar' do
    allow(imap).to receive(:authenticate).and_raise(recusa('Invalid credentials'))

    expect { servico.send(:imap_client) }.to raise_error(Net::IMAP::NoResponseError)
    expect(imap).to have_received(:disconnect)
  end

  it 'SELECT recusado fecha o socket antes de relançar' do
    allow(imap).to receive(:select).and_raise(recusa('Mailbox does not exist'))

    expect { servico.send(:imap_client) }.to raise_error(Net::IMAP::NoResponseError)
    expect(imap).to have_received(:disconnect)
  end

  it 'com_a_conexao: a exceção do bloco não é trocada por uma do fechamento' do
    allow(imap).to receive(:logout).and_raise(IOError, 'fechamento')
    allow(imap).to receive(:disconnect).and_raise(IOError, 'disconnect')

    expect { servico.com_a_conexao { raise ArgumentError, 'do bloco' } }.to raise_error(ArgumentError, 'do bloco')
  end

  context 'with the flag off (caixa que não sincroniza)' do
    before { account.disable_features!(ConversaCanal::EmailLido::FLAG) }

    it 'erro no logout propaga como no Chatwoot' do
      travel_to '26.10.2020 10:00'.to_datetime do
        allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([])
        allow(imap).to receive(:logout).and_raise(IOError, 'socket caiu')

        expect { Imap::FetchEmailService.new(channel: Channel::Email.find(channel.id)).perform }.to raise_error(IOError)
        expect(imap).not_to have_received(:disconnect)
      end
    end

    it 'autenticação recusada: a conexão do Chatwoot, sem o disconnect do fork' do
      allow(imap).to receive(:authenticate).and_raise(recusa('Invalid credentials'))

      expect { Imap::FetchEmailService.new(channel: Channel::Email.find(channel.id)).send(:imap_client) }
        .to raise_error(Net::IMAP::NoResponseError)
      expect(imap).not_to have_received(:disconnect)
    end

    it 'nem busca a janela do lido' do
      travel_to '26.10.2020 10:00'.to_datetime do
        allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([])

        Imap::FetchEmailService.new(channel: Channel::Email.find(channel.id)).perform

        expect(imap).to have_received(:search).once
        expect(ConversaCanal::EmailLidoCaixa.count).to eq(0)
      end
    end
  end

  it 'com_a_conexao: logout normal no fim' do
    expect(servico.com_a_conexao { |conexao| conexao }).to eq(imap)
    expect(imap).to have_received(:logout)
  end
end
