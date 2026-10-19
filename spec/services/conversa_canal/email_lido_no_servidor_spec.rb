require 'rails_helper'

# #1870 — painel -> servidor do cliente, uma conversa, com a conexão do job: lido vira +FLAGS (\Seen), "marcar não
# lida" vira -FLAGS no último recebido.
RSpec.describe ConversaCanal::EmailLidoNoServidor do
  subject(:servico) { described_class.new(conversation: conversation.reload) }

  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :imap_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:imap) { instance_double(Net::IMAP) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, agent_last_seen_at: 1.minute.ago) }
  let(:linhas) { ConversaCanal::EmailLido }
  # Servidor falso: { uid => Message-ID }. O UID SEARCH HEADER casa trecho, como o de verdade.
  let(:servidor) { {} }

  def recebida(source_id, criada_em)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming,
                     source_id: source_id, created_at: criada_em)
  end

  def linha(message, **atributos)
    linhas.create!({ account: account, inbox: inbox, message: message, uidvalidity: 777, sincronizado_em: Time.current }.merge(atributos))
  end

  def buscados(criterios)
    criterios.each_cons(2).filter_map { |campo, valor| valor if campo == 'Message-ID' }
  end

  def simular_servidor
    allow(imap).to receive(:uid_search) do |criterios|
      procurados = buscados(criterios)
      servidor.select { |_uid, message_id| procurados.any? { |procurado| message_id.include?(procurado) } }.keys
    end
    allow(imap).to receive(:uid_fetch) do |uids, _|
      uids.map do |uid|
        Net::IMAP::FetchData.new(uid, 'UID' => uid, 'BODY[HEADER.FIELDS (MESSAGE-ID)]' => "Message-ID: <#{servidor[uid]}>\r\n\r\n")
      end
    end
  end

  def limpar_redis
    %w[777 1 sem].each { |validade| Redis::Alfred.delete("conversa_canal:email_lido:message_ids:#{inbox.id}:#{validade}") }
  end

  before do
    account.enable_features!(ConversaCanal::EmailLido::FLAG)
    ConversaCanal::EmailLidoCaixa.create!(account: account, inbox: inbox, ponto_de_partida: 3.days.ago)
    limpar_redis
    allow(imap).to receive(:uid_store)
    allow(imap).to receive(:responses).with('UIDVALIDITY').and_yield([777])
    simular_servidor
  end

  after { limpar_redis }

  describe '#marcar_lido' do
    it 'UID STORE +FLAGS.SILENT (\Seen) pelo UID gravado e pela busca única do Message-ID' do
      gravada = recebida('a@cliente.com', 2.hours.ago)
      sem_uid = recebida('b@cliente.com', 1.hour.ago)
      linha(gravada, uid: 11, seen_no_servidor: false)
      servidor.merge!(11 => 'a@cliente.com', 12 => 'b@cliente.com')

      servico.marcar_lido(imap)

      expect(imap).to have_received(:uid_store).with(contain_exactly(11, 12), '+FLAGS.SILENT', [:Seen])
      expect(imap).to have_received(:uid_search).with(%w[HEADER Message-ID b@cliente.com]).once
      expect(linhas.where(message_id: [gravada.id, sem_uid.id]).pluck(:seen_no_servidor)).to eq([true, true])
      expect(linhas.find_by!(message_id: sem_uid.id).slice(:uid, :uidvalidity)).to eq('uid' => 12, 'uidvalidity' => 777)
    end

    it 'vários sem UID: UMA busca com OR, não uma por e-mail' do
      recebida('a@cliente.com', 3.hours.ago)
      recebida('b@cliente.com', 2.hours.ago)
      recebida('c@cliente.com', 1.hour.ago)
      servidor.merge!(1 => 'a@cliente.com', 2 => 'b@cliente.com', 3 => 'c@cliente.com')

      servico.marcar_lido(imap)

      expect(imap).to have_received(:uid_search).once
      expect(imap).to have_received(:uid_search).with(
        %w[OR HEADER Message-ID c@cliente.com OR HEADER Message-ID b@cliente.com HEADER Message-ID a@cliente.com]
      )
      expect(imap).to have_received(:uid_store).with(contain_exactly(1, 2, 3), '+FLAGS.SILENT', [:Seen])
    end

    it 'Message-ID que é trecho de outro: só o igual recebe o STORE e o UID gravado' do
      message = recebida('a@cliente.com', 1.hour.ago)
      servidor.merge!(30 => 'xa@cliente.com', 31 => 'a@cliente.com')

      servico.marcar_lido(imap)

      expect(imap).to have_received(:uid_store).with([31], '+FLAGS.SILENT', [:Seen])
      expect(linhas.find_by!(message_id: message.id).uid).to eq(31)
    end

    it 'só existe um Message-ID que contém o nosso: nenhum STORE e nenhum UID gravado' do
      message = recebida('a@cliente.com', 1.hour.ago)
      servidor[30] = 'xa@cliente.com'

      servico.marcar_lido(imap)

      expect(imap).not_to have_received(:uid_store)
      expect(linhas.find_by!(message_id: message.id).uid).to be_nil
    end

    it 'UIDVALIDITY mudou: não usa o UID velho, busca de novo' do
      linha(recebida('a@cliente.com', 1.hour.ago), uid: 3, uidvalidity: 1, seen_no_servidor: false)
      servidor[40] = 'a@cliente.com'

      servico.marcar_lido(imap)

      expect(imap).to have_received(:uid_store).with([40], '+FLAGS.SILENT', [:Seen])
    end

    it 'UIDVALIDITY ausente (nil) no servidor: usa o UID gravado sem buscar' do
      allow(imap).to receive(:responses).with('UIDVALIDITY').and_yield([])
      linha(recebida('a@cliente.com', 1.hour.ago), uid: 11, uidvalidity: nil, seen_no_servidor: false)

      servico.marcar_lido(imap)

      expect(imap).to have_received(:uid_store).with([11], '+FLAGS.SILENT', [:Seen])
      expect(imap).not_to have_received(:uid_search)
    end

    it 'nada anterior ao ponto de partida da caixa (ativação sem mudança em massa)' do
      ConversaCanal::EmailLidoCaixa.find_by!(inbox_id: inbox.id).update!(ponto_de_partida: 30.minutes.ago)
      recebida('antes@cliente.com', 1.hour.ago)
      depois = recebida('depois@cliente.com', 10.minutes.ago)
      servidor.merge!(6 => 'antes@cliente.com', 7 => 'depois@cliente.com')

      servico.marcar_lido(imap)

      expect(imap).to have_received(:uid_store).with([7], '+FLAGS.SILENT', [:Seen])
      expect(linhas.pluck(:message_id)).to eq([depois.id])
    end

    it 'e-mail que chegou depois do lido da conversa continua não lido no servidor' do
      recebida('depois@cliente.com', 1.minute.from_now)

      servico.marcar_lido(imap)

      expect(imap).not_to have_received(:uid_store)
    end

    it 'cliente tirou o \Seen lá depois da última leitura daqui: não regrava' do
      linha(recebida('a@cliente.com', 1.hour.ago), uid: 11, seen_no_servidor: false, desmarcado_no_servidor_em: 10.seconds.ago)

      expect(servico.lido_pendente?).to be(false)
      servico.marcar_lido(imap)

      expect(imap).not_to have_received(:uid_store)
    end

    it 'leitura nova aqui depois do "não lido" de lá: marca de novo' do
      linha(recebida('a@cliente.com', 1.hour.ago), uid: 11, seen_no_servidor: false, desmarcado_no_servidor_em: 10.minutes.ago)

      servico.marcar_lido(imap)

      expect(imap).to have_received(:uid_store).with([11], '+FLAGS.SILENT', [:Seen])
    end

    it 'já lido no servidor: nada a escrever' do
      linha(recebida('a@cliente.com', 1.hour.ago), uid: 11, seen_no_servidor: true)

      expect(servico.lido_pendente?).to be(false)
      servico.marcar_lido(imap)

      expect(imap).not_to have_received(:uid_store)
    end

    it 'fora do INBOX (arquivado): sem STORE, e fica como resolvido para não reabrir conexão' do
      fora = recebida('a@cliente.com', 1.hour.ago)

      servico.marcar_lido(imap)

      expect(imap).not_to have_received(:uid_store)
      expect(linhas.find_by!(message_id: fora.id).seen_no_servidor).to be(true)
      expect(described_class.new(conversation: conversation.reload).lido_pendente?).to be(false)
    end
  end

  describe '#marcar_nao_lida' do
    let!(:ultima) do
      recebida('a@cliente.com', 2.hours.ago)
      recebida('b@cliente.com', 1.hour.ago)
    end

    before do
      conversation.update!(agent_last_seen_at: ultima.created_at - 1.second)
      servidor[12] = 'b@cliente.com'
    end

    after { linhas.nao_lida_resolvida!(ultima.id) }

    it 'UID STORE -FLAGS.SILENT (\Seen) só no último recebido, e a marca pendente sai' do
      linha(ultima, uid: 12, seen_no_servidor: true)
      linhas.nao_lida_pendente!(ultima)

      servico.marcar_nao_lida(imap)

      expect(imap).to have_received(:uid_store).with([12], '-FLAGS.SILENT', [:Seen]).once
      expect(linhas.find_by!(message_id: ultima.id).seen_no_servidor).to be(false)
      expect(linhas.nao_lida_pendente?(ultima.id)).to be(false)
    end

    it 'STORE falhou: a linha não muda e a marca pendente fica para a nova tentativa' do
      linha(ultima, uid: 12, seen_no_servidor: true)
      linhas.nao_lida_pendente!(ultima)
      allow(imap).to receive(:uid_store).and_raise(IOError, 'caiu')

      expect { servico.marcar_nao_lida(imap) }.to raise_error(IOError)
      expect(linhas.find_by!(message_id: ultima.id).seen_no_servidor).to be(true)
      expect(linhas.nao_lida_pendente?(ultima.id)).to be(true)
    end

    it 'aberta de novo antes do job: não tira o \Seen e solta a marca' do
      conversation.update!(agent_last_seen_at: Time.current)
      linhas.nao_lida_pendente!(ultima)

      servico.marcar_nao_lida(imap)

      expect(imap).not_to have_received(:uid_store)
      expect(linhas.nao_lida_pendente?(ultima.id)).to be(false)
    end

    it 'preparar_nao_lida: marca o último do unread do Chatwoot (incoming.last) como pendente, sem tocar a linha' do
      linha(ultima, uid: 12, seen_no_servidor: false)

      servico.preparar_nao_lida

      expect(conversation.messages.incoming.last).to eq(ultima)
      expect(linhas.nao_lida_pendente?(ultima.id)).to be(true)
      expect(linhas.find_by!(message_id: ultima.id).seen_no_servidor).to be(false)
    end
  end

  it 'flag desligada: nada no servidor nem na fila' do
    account.disable_features!(ConversaCanal::EmailLido::FLAG)
    message = recebida('a@cliente.com', 1.hour.ago)

    servico.marcar_lido(imap)
    servico.preparar_nao_lida

    expect(imap).not_to have_received(:uid_store)
    expect(linhas.count).to eq(0)
    expect(linhas.nao_lida_pendente?(message.id)).to be(false)
  end

  it 'caixa só com encaminhamento: nada no servidor' do
    channel.update!(imap_enabled: false)
    recebida('a@cliente.com', 1.hour.ago)

    expect(servico.lido_pendente?).to be(false)
    servico.marcar_lido(imap)

    expect(imap).not_to have_received(:uid_store)
  end
end
