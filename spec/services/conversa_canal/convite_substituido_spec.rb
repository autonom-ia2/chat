require 'rails_helper'

# #1995 — o convite que o organizador mudou (SEQUENCE maior) ou cancelou num e-mail mais novo para de perguntar.
RSpec.describe ConversaCanal::ConviteSubstituido do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account, email: 'vendas@empresa.example') }
  let(:inbox) { channel.inbox }
  let(:organizadora) { create(:contact, account: account, email: 'diana@agencia.example') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: organizadora) }

  # extra: remetente (contato), conversa, carimbo (DTSTAMP) e organizador, quando não são os padrões.
  def convite_em(uid: 'uid-1@google.com', sequencia: 0, metodo: 'REQUEST', ocorrencia: nil, **extra)
    convite = { 'uid' => uid, 'sequencia' => sequencia, 'metodo' => metodo, 'ocorrencia' => ocorrencia, 'carimbo' => extra[:carimbo],
                'organizador' => { 'email' => extra.fetch(:organizador, 'diana@agencia.example') } }.compact
    create(:message, account: account, inbox: inbox, conversation: extra.fetch(:conversa, conversation), message_type: :incoming,
                     sender: extra.fetch(:remetente, organizadora), content_attributes: { email: { convite: convite } })
  end

  def convite_de(message)
    message.reload.content_attributes['email']['convite']
  end

  it 'a versão nova (SEQUENCE maior) substitui a antiga; a nova segue valendo', :aggregate_failures do
    antiga = convite_em(sequencia: 0)
    nova = convite_em(sequencia: 1)

    described_class.marcar(nova)

    expect(convite_de(antiga)).to include('substituido_por' => nova.id, 'substituido_cancelado' => false)
    expect(convite_de(nova)).not_to have_key('substituido_por')
  end

  it 'o cancelamento marca o convite como cancelado depois' do
    antiga = convite_em(sequencia: 0)
    cancelamento = convite_em(sequencia: 0, metodo: 'CANCEL')

    described_class.marcar(cancelamento)

    expect(convite_de(antiga)).to include('substituido_por' => cancelamento.id, 'substituido_cancelado' => true)
  end

  it 'vale em outra conversa da mesma caixa (o Outlook manda a mudança num e-mail novo)' do
    antiga = convite_em(sequencia: 0)
    nova = convite_em(sequencia: 2, conversa: create(:conversation, account: account, inbox: inbox, contact: organizadora))

    described_class.marcar(nova)

    expect(convite_de(antiga)['substituido_por']).to eq(nova.id)
  end

  it 'fora de ordem: o convite antigo que chega depois já nasce substituído', :aggregate_failures do
    nova = convite_em(sequencia: 3)
    antiga = convite_em(sequencia: 1)

    described_class.marcar(antiga)

    expect(convite_de(antiga)['substituido_por']).to eq(nova.id)
    expect(convite_de(nova)).not_to have_key('substituido_por')
  end

  it 'de outro remetente não substitui (um terceiro não cancela o convite de outro)' do
    antiga = convite_em(sequencia: 0)
    intrusa = create(:contact, account: account, email: 'intrusa@outra.example')

    described_class.marcar(convite_em(sequencia: 5, metodo: 'CANCEL', remetente: intrusa))

    expect(convite_de(antiga)).not_to have_key('substituido_por')
  end

  it 'outra reunião (outro UID) não é tocada' do
    antiga = convite_em(uid: 'outra@google.com', sequencia: 0)

    described_class.marcar(convite_em(sequencia: 4))

    expect(convite_de(antiga)).not_to have_key('substituido_por')
  end

  it 'mudar uma ocorrência não substitui a série; cancelar a série substitui a ocorrência', :aggregate_failures do
    serie = convite_em(sequencia: 0)
    ocorrencia = convite_em(sequencia: 1, ocorrencia: 1_793_000_000)

    described_class.marcar(ocorrencia)
    expect(convite_de(serie)).not_to have_key('substituido_por')

    cancelamento = convite_em(sequencia: 2, metodo: 'CANCEL')
    described_class.marcar(cancelamento)
    expect(convite_de(ocorrencia)['substituido_por']).to eq(cancelamento.id)
    expect(convite_de(serie)['substituido_por']).to eq(cancelamento.id)
  end

  it 'o mesmo convite reenviado (mesma SEQUENCE) não substitui: a resposta já dada segue valendo' do
    antiga = convite_em(sequencia: 1, carimbo: 100)

    described_class.marcar(convite_em(sequencia: 1, carimbo: 200))

    expect(convite_de(antiga)).not_to have_key('substituido_por')
  end

  it 'mesma SEQUENCE: vale o DTSTAMP, e o REQUEST que readiciona a caixa não nasce cancelado', :aggregate_failures do
    cancelamento = convite_em(sequencia: 0, metodo: 'CANCEL', carimbo: 100)
    readicionado = convite_em(sequencia: 0, carimbo: 200)

    described_class.marcar(readicionado)

    expect(convite_de(readicionado)).not_to have_key('substituido_por')
    expect(convite_de(cancelamento)).to include('substituido_por' => readicionado.id, 'substituido_cancelado' => false)
  end

  it 'REQUEST, CANCEL e o REQUEST que readiciona: o primeiro aponta para o último, sem "cancelada"', :aggregate_failures do
    primeiro = convite_em(sequencia: 0, carimbo: 100)
    cancelamento = convite_em(sequencia: 0, metodo: 'CANCEL', carimbo: 200)
    readicionado = convite_em(sequencia: 0, carimbo: 300)

    described_class.marcar(readicionado)

    expect(convite_de(primeiro)).to include('substituido_por' => readicionado.id, 'substituido_cancelado' => false)
    expect(convite_de(cancelamento)['substituido_por']).to eq(readicionado.id)
    expect(convite_de(readicionado)).not_to have_key('substituido_por')
  end

  it 'dois e-mails juntos: a marca não volta para uma versão mais velha que a já marcada', :aggregate_failures do
    antiga = convite_em(sequencia: 0)
    mudanca = convite_em(sequencia: 1)
    cancelamento = convite_em(sequencia: 2, metodo: 'CANCEL')
    described_class.marcar(cancelamento)

    # O job da mudança leu a reunião antes do cancelamento chegar: só vê a antiga e a mudança.
    servico = described_class.new(mudanca)
    allow(servico).to receive(:mesma_reuniao).and_return([antiga, mudanca])
    servico.perform

    expect(convite_de(antiga)).to include('substituido_por' => cancelamento.id, 'substituido_cancelado' => true)
  end

  it 'de outro organizador não substitui, mesmo com o UID igual' do
    antiga = convite_em(sequencia: 0)

    described_class.marcar(convite_em(sequencia: 3, organizador: 'outra@agencia.example'))

    expect(convite_de(antiga)).not_to have_key('substituido_por')
  end

  it 'guarda a conversa do convite novo e marca mesmo com a conversa no limite de mensagens por minuto', :aggregate_failures do
    antiga = convite_em(sequencia: 0)
    outra = create(:conversation, account: account, inbox: inbox, contact: organizadora)
    nova = convite_em(sequencia: 1, conversa: outra)
    allow(Limits).to receive(:conversation_message_per_minute_limit).and_return(1)

    described_class.marcar(nova)

    expect(convite_de(antiga)).to include('substituido_por' => nova.id, 'substituido_na_conversa' => outra.display_id)
  end

  describe 'a chave do UID (#2042)' do
    it 'o e-mail recebido com convite guarda a chave; o sem convite, não', :aggregate_failures do
      expect(convite_em.reload.additional_attributes['convite_uid_sha256']).to eq(Digest::SHA256.hexdigest('uid-1@google.com'))
      sem_convite = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi')
      expect(sem_convite.reload.additional_attributes).not_to have_key('convite_uid_sha256')
    end

    it 'UID enorme ou com aspas: a mensagem é gravada e a versão anterior é achada', :aggregate_failures do
      uid = "#{'x' * 20_000}\"aspas\"\\barra"
      antiga = convite_em(uid: uid, sequencia: 0)
      nova = convite_em(uid: uid, sequencia: 1)

      described_class.marcar(nova)

      expect(convite_de(antiga)['substituido_por']).to eq(nova.id)
    end

    it 'a condição da busca casa com o índice parcial, sem a ordem do default_scope', :aggregate_failures do
      consulta = described_class.pela_chave('uid-1@google.com')
      plano = Message.transaction do
        Message.connection.execute('SET LOCAL enable_seqscan = off')
        Message.connection.select_values("EXPLAIN #{consulta.to_sql}").join("\n")
      end

      expect(consulta.to_sql).not_to include('ORDER BY')
      expect(plano).to include('index_messages_on_convite_uid_sha256')
    end
  end

  it 'o e-mail recebido com convite agenda a conferência', :aggregate_failures do
    expect { convite_em }.to have_enqueued_job(ConversaCanal::ConviteSubstituidoJob)
    expect do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi')
    end.not_to have_enqueued_job(ConversaCanal::ConviteSubstituidoJob)
  end
end
