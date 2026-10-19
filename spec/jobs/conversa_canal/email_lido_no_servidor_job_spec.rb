require 'rails_helper'

# #1870 — o lido no servidor do cliente sai do request: fila por caixa, um job por caixa, espera pelo lock da importação.
describe ConversaCanal::EmailLidoNoServidorJob do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :imap_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:outra) { create(:conversation, account: account, inbox: inbox) }
  let(:imap) { instance_double(Net::IMAP) }
  let(:servico) { instance_double(ConversaCanal::EmailLidoNoServidor, marcar_lido: nil, marcar_nao_lida: nil) }
  let(:tracker) { instance_double(ChatwootExceptionTracker, capture_exception: true) }
  let(:fila) { ConversaCanal::FilaDoEmailLido.new(inbox.id) }
  let(:chave_do_lock) { ConversaCanal::LockDaCaixa.chave(inbox) }
  let(:chaves) do
    ["conversa_canal:email_lido:fila:#{inbox.id}", "conversa_canal:email_lido:job:#{inbox.id}", chave_do_lock,
     "conversa_canal:email_lido:falha_rastreada:#{inbox.id}"]
  end

  def na_fila
    Redis::Alfred.with { |conn| conn.smembers("conversa_canal:email_lido:fila:#{inbox.id}") }
  end

  def limpar_redis
    chaves.each { |chave| Redis::Alfred.delete(chave) }
  end

  def resposta(nome, texto)
    Net::IMAP::TaggedResponse.new('A1', nome, Net::IMAP::ResponseText.new(nil, texto), '')
  end

  before do
    account.enable_features!(ConversaCanal::EmailLido::FLAG)
    limpar_redis
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(authenticate: nil, select: nil, logout: nil, disconnect: nil)
    allow(ConversaCanal::EmailLidoNoServidor).to receive(:new).and_return(servico)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
  end

  after { limpar_redis }

  describe '.agendar' do
    it 'um job por caixa, na fila low, para o fim da espera; aberturas e conversas seguidas juntam nele' do
      freeze_time do
        3.times { described_class.agendar(conversation, described_class::LIDO) }
        described_class.agendar(outra, described_class::NAO_LIDA)

        expect(described_class).to have_been_enqueued.exactly(:once)
        expect(described_class).to have_been_enqueued.with(inbox).on_queue('low').at(described_class::ESPERA.from_now)
        expect(na_fila).to contain_exactly("lido:#{conversation.id}", "nao_lida:#{outra.id}")
      end
    end
  end

  describe '#perform' do
    it 'escreve todos os pedidos da caixa numa conexão só e esvazia a fila' do
      described_class.agendar(conversation, described_class::LIDO)
      described_class.agendar(outra, described_class::NAO_LIDA)

      described_class.perform_now(inbox)

      expect(Net::IMAP).to have_received(:new).once
      expect(servico).to have_received(:marcar_lido).with(imap).once
      expect(servico).to have_received(:marcar_nao_lida).with(imap).once
      expect(fila.pendente?).to be(false)
      expect(Redis::Alfred.get(chave_do_lock)).to be_nil
    end

    it 'fila vazia: nem conecta' do
      described_class.perform_now(inbox)

      expect(Net::IMAP).not_to have_received(:new)
    end

    it 'teto de conversas por conexão: o resto vai num job novo' do
      conversas = create_list(:conversation, described_class::POR_JOB + 2, account: account, inbox: inbox)
      conversas.each { |conversa| fila.adicionar(conversa.id, described_class::LIDO) }

      described_class.perform_now(inbox)

      expect(servico).to have_received(:marcar_lido).exactly(described_class::POR_JOB).times
      expect(na_fila.size).to eq(2)
      expect(described_class).to have_been_enqueued.with(inbox)
    end

    it 'flag desligada: esvazia a fila sem conectar' do
      account.disable_features!(ConversaCanal::EmailLido::FLAG)
      fila.adicionar(conversation.id, described_class::LIDO)

      described_class.perform_now(Inbox.find(inbox.id))

      expect(Net::IMAP).not_to have_received(:new)
      expect(fila.pendente?).to be(false)
    end
  end

  describe 'caixa ocupada pela importação' do
    it 'espera por tempo e a ação acontece depois, quando a caixa libera' do
      described_class.agendar(conversation, described_class::NAO_LIDA)
      Redis::Alfred.set(chave_do_lock, 'lock-da-importacao', ex: 300)

      freeze_time do
        described_class.perform_now(inbox)

        expect(servico).not_to have_received(:marcar_nao_lida)
        expect(described_class).to have_been_enqueued.with(inbox, Time.current.to_i, 0).at(described_class::ESPERA_DO_LOCK.from_now)
        expect(Redis::Alfred.get(chave_do_lock)).to eq('lock-da-importacao')
      end

      Redis::Alfred.delete(chave_do_lock)
      described_class.perform_now(inbox, 1.minute.ago.to_i, 0)

      expect(servico).to have_received(:marcar_nao_lida).with(imap).once
      expect(fila.pendente?).to be(false)
    end

    it 'passou do teto: desiste com o estado consistente (fila vazia, marca de não lida solta, linha intacta)' do
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, source_id: 'a@c.com')
      ConversaCanal::EmailLido.create!(account: account, inbox: inbox, message: message, uid: 5, seen_no_servidor: true,
                                       sincronizado_em: Time.current)
      ConversaCanal::EmailLido.nao_lida_pendente!(message)
      described_class.agendar(conversation, described_class::NAO_LIDA)
      Redis::Alfred.set(chave_do_lock, 'lock-da-importacao', ex: 300)

      described_class.perform_now(inbox, (described_class::TETO_DA_ESPERA + 1.second).ago.to_i, 0)

      expect(described_class).not_to have_been_enqueued.with(inbox, anything, anything)
      expect(fila.pendente?).to be(false)
      expect(ConversaCanal::EmailLido.nao_lida_pendente?(message.id)).to be(false)
      expect(ConversaCanal::EmailLido.find_by!(message_id: message.id).seen_no_servidor).to be(true)
      # Desistir nunca é silencioso: log e rastreio (dentro do limite de um por caixa na hora).
      expect(tracker).to have_received(:capture_exception).once
    end

    it 'perdeu o lock no meio (passou do TTL e a importação pegou): para e volta depois com o que falta' do
      described_class.agendar(conversation, described_class::LIDO)
      described_class.agendar(outra, described_class::LIDO)
      allow(servico).to receive(:marcar_lido) { Redis::Alfred.set(chave_do_lock, 'lock-da-importacao', ex: 300) }

      described_class.perform_now(inbox)

      expect(servico).to have_received(:marcar_lido).once
      expect(na_fila.size).to eq(1)
      reagendado = have_been_enqueued.with(inbox, be_within(2).of(Time.current.to_i), 1)
      expect(described_class).to reagendado.at(be_within(2.seconds).of(described_class::ESPERA_DO_LOCK.from_now))
    end

    it 'lock perdido: o relógio da espera segue no reagendamento' do
      described_class.agendar(conversation, described_class::LIDO)
      described_class.agendar(outra, described_class::LIDO)
      allow(servico).to receive(:marcar_lido) { Redis::Alfred.set(chave_do_lock, 'lock-da-importacao', ex: 300) }

      inicio = 4.minutes.ago.to_i
      described_class.perform_now(inbox, inicio, 0)

      expect(described_class).to have_been_enqueued.with(inbox, inicio, 1)
    end

    it 'lock perdido na primeira vez, sem espera antes: o relógio da espera começa na perda' do
      described_class.agendar(conversation, described_class::LIDO)
      described_class.agendar(outra, described_class::LIDO)
      allow(servico).to receive(:marcar_lido) { Redis::Alfred.set(chave_do_lock, 'lock-da-importacao', ex: 300) }

      freeze_time do
        described_class.perform_now(inbox)

        expect(described_class).to have_been_enqueued.with(inbox, Time.current.to_i, 1)
      end
    end

    it 'cadeia longa de esperas: a marca de não lida pendente é renovada e vale até a escrita' do
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, source_id: 'a@c.com')
      ConversaCanal::EmailLido.nao_lida_pendente!(message)
      described_class.agendar(conversation, described_class::NAO_LIDA)
      Redis::Alfred.set(chave_do_lock, 'lock-da-importacao', ex: 3600)

      3.times do
        travel(ConversaCanal::EmailLido::NAO_LIDA_PENDENTE - 5.minutes)
        described_class.perform_now(inbox, 1.minute.ago.to_i, 0)
        expect(ConversaCanal::EmailLido.nao_lida_pendente?(message.id)).to be(true)
      end

      Redis::Alfred.delete(chave_do_lock)
      allow(servico).to receive(:marcar_nao_lida) { expect(ConversaCanal::EmailLido.nao_lida_pendente?(message.id)).to be(true) }
      described_class.perform_now(inbox, 1.minute.ago.to_i, 0)

      expect(servico).to have_received(:marcar_nao_lida).with(imap).once
    ensure
      ConversaCanal::EmailLido.nao_lida_resolvida!(message.id)
    end

    it 'lock perdido além do teto de perdas: desiste, esvazia a fila e rastreia' do
      described_class.agendar(conversation, described_class::LIDO)
      described_class.agendar(outra, described_class::LIDO)
      allow(servico).to receive(:marcar_lido) { Redis::Alfred.set(chave_do_lock, 'lock-da-importacao', ex: 300) }

      described_class.perform_now(inbox, nil, described_class::PERDAS_DO_LOCK)

      expect(described_class).not_to have_been_enqueued.with(inbox, anything, anything)
      expect(fila.pendente?).to be(false)
      expect(ChatwootExceptionTracker).to have_received(:new)
        .with(having_attributes(message: 'ConversaCanal::LockDaCaixa::LockPerdido'), account: account)
    end
  end

  describe 'pedidos que chegam durante a escrita ou a desistência' do
    it 'o mesmo pedido de novo durante a escrita não se perde: fica na fila e agenda o job' do
      described_class.agendar(conversation, described_class::LIDO)
      clear_enqueued_jobs
      allow(servico).to receive(:marcar_lido) { described_class.agendar(conversation, described_class::LIDO) }

      described_class.perform_now(inbox)

      expect(na_fila).to eq(["lido:#{conversation.id}"])
      expect(described_class).to have_been_enqueued.with(inbox).exactly(:once)
    end

    it 'pedido que entra depois de a fila ser esvaziada na desistência é reagendado' do
      described_class.agendar(conversation, described_class::LIDO)
      clear_enqueued_jobs
      allow(imap).to receive(:authenticate).and_raise(Net::IMAP::NoResponseError.new(resposta('NO', 'Invalid credentials')))
      # Entra entre o MULTI (fila + agendamento) e o fim da desistência, sem ter agendado o próprio job.
      allow(tracker).to receive(:capture_exception) { fila.adicionar(outra.id, described_class::LIDO) }

      described_class.perform_now(inbox)

      expect(na_fila).to eq(["lido:#{outra.id}"])
      expect(described_class).to have_been_enqueued.with(inbox).exactly(:once)
    end
  end

  describe 'erro de infraestrutura numa conversa é transitório, nunca envenenado' do
    before do
      described_class.agendar(conversation, described_class::LIDO)
      described_class.agendar(outra, described_class::LIDO)
      clear_enqueued_jobs
    end

    it 'deadlock numa conversa: reagenda e não descarta' do
      allow(servico).to receive(:marcar_lido).and_raise(ActiveRecord::Deadlocked, 'deadlock')

      described_class.perform_now(inbox)

      expect(na_fila.size).to eq(2)
      expect(described_class).to have_been_enqueued.with(inbox).once
      expect(tracker).not_to have_received(:capture_exception)
    end

    it 'Redis fora ao renovar o lock: o resto do lote volta para a fila e o job tenta de novo' do
      allow(ConversaCanal::LockDaCaixa).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |lock| allow(lock).to receive(:renovar!).and_raise(Redis::CannotConnectError, 'redis') }
      end

      described_class.perform_now(inbox)

      expect(servico).to have_received(:marcar_lido).once
      expect(na_fila.size).to eq(1)
      expect(described_class).to have_been_enqueued.with(inbox).once
    end
  end

  describe 'pedido envenenado' do
    it 'erro inesperado numa conversa: registra a classe, descarta aquele pedido e segue o lote' do
      message = create(:message, conversation: outra, account: account, inbox: inbox, message_type: :incoming, source_id: 'b@c.com')
      ConversaCanal::EmailLido.nao_lida_pendente!(message)
      described_class.agendar(conversation, described_class::LIDO)
      described_class.agendar(outra, described_class::NAO_LIDA)
      clear_enqueued_jobs
      allow(servico).to receive(:marcar_nao_lida).and_raise(NoMethodError, 'detalhe interno')

      described_class.perform_now(inbox)

      expect(servico).to have_received(:marcar_lido).with(imap).once
      expect(fila.pendente?).to be(false)
      expect(described_class).not_to have_been_enqueued
      expect(ConversaCanal::EmailLido.nao_lida_pendente?(message.id)).to be(false)
      expect(ChatwootExceptionTracker).to have_received(:new)
        .with(having_attributes(class: ConversaCanal::FalhaDoEmailLido, message: 'NoMethodError'), account: account)
    end

    it 'falha ao descartar não devolve o envenenado para a fila' do
      described_class.agendar(outra, described_class::NAO_LIDA)
      clear_enqueued_jobs
      allow(servico).to receive(:marcar_nao_lida).and_raise(NoMethodError, 'detalhe interno')
      allow(ConversaCanal::FalhaDoEmailLido).to receive(:registrar).and_raise(Redis::CannotConnectError, 'redis')

      described_class.perform_now(inbox)

      expect(fila.pendente?).to be(false)
      expect(described_class).not_to have_been_enqueued
    end
  end

  describe 'falhas' do
    before { described_class.agendar(conversation, described_class::LIDO) }

    it 'transitório (rede): tenta de novo e o pedido continua na fila' do
      allow(servico).to receive(:marcar_lido).and_raise(IOError, 'caiu')

      described_class.perform_now(inbox)

      # O do agendar e o da nova tentativa.
      expect(described_class).to have_been_enqueued.with(inbox).twice
      expect(fila.pendente?).to be(true)
      expect(tracker).not_to have_received(:capture_exception)
    end

    it 'BYE no meio: transitório' do
      allow(servico).to receive(:marcar_lido).and_raise(Net::IMAP::ByeResponseError.new(resposta('BYE', 'logout')))

      described_class.perform_now(inbox)

      # O do agendar e o da nova tentativa.
      expect(described_class).to have_been_enqueued.with(inbox).twice
    end

    it 'esgotadas as tentativas: desiste, registra só a classe e esvazia a fila' do
      allow(servico).to receive(:marcar_lido).and_raise(IOError, 'resposta do provedor com segredo')

      expect { perform_enqueued_jobs { described_class.perform_later(inbox) } }.not_to raise_error
      expect(servico).to have_received(:marcar_lido).exactly(described_class::TENTATIVAS).times
      expect(tracker).to have_received(:capture_exception).once
      expect(ChatwootExceptionTracker).to have_received(:new)
        .with(having_attributes(class: ConversaCanal::FalhaDoEmailLido, message: 'IOError'), account: account)
      expect(fila.pendente?).to be(false)
    end

    it 'credencial recusada: não tenta de novo, desiste e registra' do
      allow(imap).to receive(:authenticate).and_raise(Net::IMAP::NoResponseError.new(resposta('NO', 'Invalid credentials')))

      expect { perform_enqueued_jobs { described_class.perform_later(inbox) } }.not_to raise_error
      expect(Net::IMAP).to have_received(:new).once
      expect(tracker).to have_received(:capture_exception).once
      expect(fila.pendente?).to be(false)
    end

    it 'só a primeira falha persistente da caixa na hora vai ao rastreador; as outras, só ao log' do
      allow(imap).to receive(:authenticate).and_raise(Net::IMAP::NoResponseError.new(resposta('NO', 'Invalid credentials')))

      perform_enqueued_jobs { described_class.perform_later(inbox) }
      described_class.agendar(conversation, described_class::LIDO)
      perform_enqueued_jobs { described_class.perform_later(inbox) }

      expect(tracker).to have_received(:capture_exception).once
    end
  end
end
