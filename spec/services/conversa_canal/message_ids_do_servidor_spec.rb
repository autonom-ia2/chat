require 'rails_helper'

# #1870 — Message-ID por UID, do cabeçalho, com cache por (caixa, UIDVALIDITY, UID).
RSpec.describe ConversaCanal::MessageIdsDoServidor do
  subject(:message_ids) { described_class.new(imap: imap, inbox: inbox, uidvalidity: 777) }

  let(:inbox) { create(:inbox) }
  let(:imap) { instance_double(Net::IMAP) }
  let(:chave) { "conversa_canal:email_lido:message_ids:#{inbox.id}:777" }

  before { Redis::Alfred.delete(chave) }
  after { Redis::Alfred.delete(chave) }

  it 'acha a seção sem diferenciar maiúsculas (servidor que devolve body[header.fields (message-id)])' do
    allow(imap).to receive(:uid_fetch).and_return(
      [Net::IMAP::FetchData.new(1, 'UID' => 5, 'body[header.fields (message-id)]' => "Message-ID: <a@cliente.com>\r\n\r\n")]
    )

    expect(message_ids.de([5])).to eq(5 => 'a@cliente.com')
  end

  it 'lembra no minuto seguinte, sem pedir de novo' do
    allow(imap).to receive(:uid_fetch).and_return(
      [Net::IMAP::FetchData.new(1, 'UID' => 5, 'BODY[HEADER.FIELDS (MESSAGE-ID)]' => "Message-ID: <a@cliente.com>\r\n\r\n")]
    )
    message_ids.de([5])

    expect(described_class.new(imap: imap, inbox: inbox, uidvalidity: 777).de([5])).to eq(5 => 'a@cliente.com')
    expect(imap).to have_received(:uid_fetch).once
  end

  it 'cabeçalho sem Message-ID: guarda vazio e não pede de novo' do
    allow(imap).to receive(:uid_fetch).and_return([Net::IMAP::FetchData.new(1, 'UID' => 5, 'BODY[HEADER.FIELDS (MESSAGE-ID)]' => "\r\n")])

    expect(message_ids.de([5])).to eq({})
    message_ids.de([5])
    expect(imap).to have_received(:uid_fetch).once
  end

  it 'seção que não veio na resposta: não guarda nada, e pede de novo na próxima' do
    allow(imap).to receive(:uid_fetch).and_return([Net::IMAP::FetchData.new(1, 'UID' => 5)])

    expect(message_ids.de([5])).to eq({})
    message_ids.de([5])
    expect(imap).to have_received(:uid_fetch).twice
    expect(Redis::Alfred.hget(chave, '5')).to be_nil
  end
end
