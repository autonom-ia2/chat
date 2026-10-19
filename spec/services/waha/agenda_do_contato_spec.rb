require 'rails_helper'

# #1865 — o contato fica na agenda do aparelho antes do envio pelo WhatsApp API, sem sobrescrever o nome do dono.
describe Waha::AgendaDoContato do
  let(:account) { create(:account) }
  let(:client) { instance_double(Waha::Client) }
  let(:contact) { create(:contact, account: account, name: 'Lays Ferreira', phone_number: '+5511913716185') }
  let(:chat_id) { '5511913716185@c.us' }
  let(:chave) { "waha:agenda:sessao-1:#{chat_id}" }

  def garantir(contato = contact, **)
    described_class.new(client: client, session: 'sessao-1', contact: contato, **).garantir
  end

  def na_agenda(nome)
    allow(client).to receive(:contact).with(session: 'sessao-1', chat_id: chat_id, timeout: 5).and_return({ 'name' => nome, 'pushname' => 'X' })
  end

  before do
    allow(client).to receive(:upsert_contact)
    allow(Rails.logger).to receive(:info)
    Redis::Alfred.delete(chave)
  end

  after { Redis::Alfred.delete(chave) }

  it 'contato que o motor não conhece (404) conta como agenda vazia e é salvo' do
    allow(client).to receive(:contact).and_raise(Waha::Client::NotFound, 'WAHA GET -> 404')

    garantir

    expect(client).to have_received(:upsert_contact)
  end

  it 'depois de uma falha não tenta de novo a cada mensagem' do
    allow(client).to receive(:contact).and_raise(Waha::Client::Timeout, 'sem resposta')

    2.times { garantir }

    expect(client).to have_received(:contact).once
    expect(Redis::Alfred.ttl(chave)).to be_between(1, described_class::FALHA_TTL)
  end

  it 'a segunda mensagem ao mesmo contato espera a primeira decidir e não repete o motor' do
    Redis::Alfred.set("#{chave}:trava", '1', nx: true, ex: 15)
    allow(client).to receive(:contact)
    allow(Kernel).to receive(:sleep) { Redis::Alfred.delete("#{chave}:trava") }

    garantir

    expect(Kernel).to have_received(:sleep).once
    expect(client).not_to have_received(:contact)
  end

  it 'a marca no Redis não guarda o nome do contato' do
    na_agenda('')

    garantir

    expect(Redis::Alfred.get(chave)).not_to include('Lays')
    expect(Redis::Alfred.get(chave)).not_to include(Digest::SHA256.hexdigest('Lays Ferreira')[0, 16])
  end

  it 'salva pelo número quando a agenda não tem o contato, dividindo nome e sobrenome' do
    na_agenda('')

    garantir

    expect(client).to have_received(:upsert_contact)
      .with(session: 'sessao-1', chat_id: chat_id, first_name: 'Lays', last_name: 'Ferreira', timeout: 5)
  end

  it 'manda o nome inteiro em firstName quando não há sobrenome' do
    contact.update!(name: 'Lili')
    na_agenda('')

    garantir

    expect(client).to have_received(:upsert_contact).with(hash_including(first_name: 'Lili', last_name: ''))
  end

  it 'não sobrescreve o nome que o dono salvou no celular' do
    na_agenda('Lays do seguro')

    garantir

    expect(client).not_to have_received(:upsert_contact)
  end

  it 'não lê de novo depois de decidir que o nome é do dono' do
    na_agenda('Lays do seguro')

    2.times { garantir }

    expect(client).to have_received(:contact).once
  end

  it 'não salva quando a agenda já tem o mesmo nome' do
    na_agenda('Lays Ferreira')

    garantir

    expect(client).not_to have_received(:upsert_contact)
  end

  it 'salva uma vez só: a segunda mensagem não consulta o motor' do
    na_agenda('')

    2.times { garantir }

    expect(client).to have_received(:contact).once
    expect(client).to have_received(:upsert_contact).once
  end

  it 'atualiza o nome que nós salvamos quando ele muda no chat2you' do
    na_agenda('')
    garantir
    contact.update!(name: 'Lays Ferreira Souza')
    na_agenda('Lays Ferreira')

    garantir

    expect(client).to have_received(:upsert_contact).with(hash_including(first_name: 'Lays', last_name: 'Ferreira Souza'))
  end

  it 'sem a marca do Redis, um nome diferente na agenda conta como do dono' do
    contact.update!(name: 'Lays Ferreira Souza')
    na_agenda('Lays Ferreira')

    garantir

    expect(client).not_to have_received(:upsert_contact)
  end

  it 'ignora contato sem nome e contato cujo nome é o telefone' do
    allow(client).to receive(:contact)
    garantir(create(:contact, account: account, name: '', phone_number: '+5511900000001'))
    garantir(create(:contact, account: account, name: '+55 11 90000-0002', phone_number: '+5511900000002'))

    expect(client).not_to have_received(:contact)
  end

  it 'ignora grupo e endereço @lid' do
    allow(client).to receive(:contact)
    garantir(chat_id: '120363000000000000@g.us')
    garantir(chat_id: '189932094144551@lid')

    expect(client).not_to have_received(:contact)
  end

  it 'sem telefone, usa o jid que o conector guardou' do
    sem_fone = create(:contact, account: account, name: 'Ana', phone_number: nil, custom_attributes: { 'waha_whatsapp_jid' => '5511955554444@c.us' })

    expect(described_class.chat_id_de(sem_fone)).to eq('5511955554444@c.us')
  end

  it 'nunca levanta: falha do motor vira log só com a classe' do
    allow(client).to receive(:contact).and_raise(Waha::Client::Timeout, 'WAHA GET /api/contacts sem resposta: segredo')

    expect { garantir }.not_to raise_error
    expect(Rails.logger).to have_received(:info).with("[waha][agenda] contato não salvo session=sessao-1 contact=#{contact.id} Waha::Client::Timeout")
  end
end
