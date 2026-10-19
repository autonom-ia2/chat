require 'rails_helper'

# #1870 — abrir a conversa de e-mail no painel marca lido no servidor do cliente; "marcar não lida" tira o \Seen lá; o
# servidor manda o lido e o não lido do último e-mail de volta. Ciclos encadeados com um servidor IMAP falso.
RSpec.describe 'Read status of email synced with the IMAP server', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_email, :imap_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:agora) { Time.zone.parse('2020-10-26 10:00') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, agent_last_seen_at: agora - 2.hours) }
  let(:imap) { instance_double(Net::IMAP) }
  let(:job) { ConversaCanal::EmailLidoNoServidorJob }
  let(:servidor) { { 21 => { message_id: 'ultimo@cliente.com', seen: false } } }
  let!(:ultima) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming,
                     source_id: 'ultimo@cliente.com', created_at: agora - 1.hour)
  end

  def limpar_debounce
    %w[fila job].each { |tipo| Redis::Alfred.delete("conversa_canal:email_lido:#{tipo}:#{inbox.id}") }
  end

  def limpar_redis
    limpar_debounce
    Redis::Alfred.delete(ConversaCanal::LockDaCaixa.chave(inbox))
    Redis::Alfred.delete("conversa_canal:email_lido:message_ids:#{inbox.id}:777")
    Redis::Alfred.delete("conversa_canal:email_lido:falha_rastreada:#{inbox.id}")
    ConversaCanal::EmailLido.nao_lida_resolvida!(ultima.id)
  end

  # O servidor falso guarda o \Seen: UID STORE muda, SEARCH/FETCH/UID FETCH leem.
  def estado_de(seq)
    uid = servidor.keys[seq - 1]
    Net::IMAP::FetchData.new(seq, 'UID' => uid, 'FLAGS' => servidor[uid][:seen] ? [:Seen] : [])
  end

  def cabecalho_de(uid)
    Net::IMAP::FetchData.new(uid, 'UID' => uid, 'BODY[HEADER.FIELDS (MESSAGE-ID)]' => "Message-ID: <#{servidor[uid][:message_id]}>\r\n\r\n")
  end

  def simular_escrita
    allow(imap).to receive(:uid_store) { |uids, acao, _flags| uids.each { |uid| servidor[uid][:seen] = acao.start_with?('+') } }
    allow(imap).to receive(:uid_search) { |(_, _, message_id)| servidor.select { |_, e| e[:message_id] == message_id }.keys }
  end

  def simular_leitura
    allow(imap).to receive(:search).with(%w[SINCE 24-Oct-2020]) { (1..servidor.size).to_a }
    allow(imap).to receive(:fetch).with(anything, %w[UID FLAGS]) { |seqs, _| seqs.map { |seq| estado_de(seq) } }
    allow(imap).to receive(:uid_fetch) { |uids, _| uids.map { |uid| cabecalho_de(uid) } }
  end

  def abrir(**params)
    limpar_debounce
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/update_last_seen",
         headers: agent.create_new_auth_token, params: params, as: :json
  end

  def marcar_nao_lida
    limpar_debounce
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/unread",
         headers: agent.create_new_auth_token, as: :json
  end

  def importar
    # Canal relido, como no job da importação: a conta em cache no objeto do teste não vê a flag ligada depois.
    Imap::FetchEmailService.new(channel: Channel::Email.find(channel.id)).perform
  end

  def lido_aqui?
    conversation.reload.agent_last_seen_at >= ultima.created_at
  end

  around { |exemplo| travel_to(agora) { exemplo.run } }

  before do
    account.enable_features!(ConversaCanal::EmailLido::FLAG)
    ConversaCanal::EmailLidoCaixa.create!(account: account, inbox: inbox, ponto_de_partida: agora - 1.day)
    create(:inbox_member, user: agent, inbox: inbox)
    limpar_redis
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive_messages(authenticate: nil, select: nil, logout: nil)
    allow(imap).to receive(:responses).with('UIDVALIDITY').and_yield([777])
    allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([])
    simular_escrita
    simular_leitura
  end

  after { limpar_redis }

  it 'abrir com read_receipt: o lido sai do request e o job marca \Seen no servidor' do
    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }

    expect(response).to have_http_status(:success)
    expect(lido_aqui?).to be(true)
    expect(imap).to have_received(:uid_store).with([21], '+FLAGS.SILENT', [:Seen])
  end

  it 'não fala com o servidor dentro do request' do
    abrir(read_receipt: true)

    expect(job).to have_been_enqueued.with(inbox).on_queue('low')
    expect(Net::IMAP).not_to have_received(:new)
  end

  it 'sem read_receipt (marcar como lida pela lista, sincronização) não enfileira' do
    abrir

    expect(job).not_to have_been_enqueued
  end

  it 'ciclo: lido no painel -> STORE -> importação -> nada reverte' do
    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }
    expect(servidor[21][:seen]).to be(true)

    2.times { importar }

    expect(lido_aqui?).to be(true)
    expect(job).not_to have_been_enqueued
  end

  it 'ciclo: não lida no painel -> -FLAGS -> importação -> continua não lida' do
    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }
    importar

    perform_enqueued_jobs(only: job) { marcar_nao_lida }

    expect(response).to have_http_status(:success)
    expect(conversation.reload.agent_last_seen_at).to eq(ultima.created_at - 1.second)
    expect(servidor[21][:seen]).to be(false)
    2.times { importar }
    expect(lido_aqui?).to be(false)
  end

  it 'ciclo: não lida no painel com -FLAGS falhando -> servidor segue \Seen -> a importação não desfaz' do
    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }
    importar
    allow(imap).to receive(:uid_store).with([21], '-FLAGS.SILENT', [:Seen]).and_raise(IOError, 'caiu')

    perform_enqueued_jobs(only: job) { marcar_nao_lida }

    expect(servidor[21][:seen]).to be(true)
    importar
    expect(lido_aqui?).to be(false)
  end

  it 'ciclo: não lida com o job atrasado (20 min): a leitura no Gmail no meio não desfaz, e o job ainda escreve' do
    abrir(read_receipt: true)
    importar
    marcar_nao_lida
    servidor[21][:seen] = true

    travel 20.minutes
    importar

    expect(lido_aqui?).to be(false)
    perform_enqueued_jobs(only: job)
    expect(servidor[21][:seen]).to be(false)
    importar
    expect(lido_aqui?).to be(false)
  end

  it '"não lida" que falha no Chatwoot (super) solta a marca de pendente' do
    allow(ConversaCanal::LidoDaConversa).to receive(:new).and_raise(StandardError, 'caiu')

    marcar_nao_lida

    expect(response).to have_http_status(:internal_server_error)
    expect(ConversaCanal::EmailLido.nao_lida_pendente?(ultima.id)).to be(false)
  end

  it '"não lida" que não consegue agendar o job tira o pedido da fila, solta a marca e responde ok' do
    allow(ConversaCanal::EmailLidoNoServidorJob).to receive(:agendar_se_pendente).and_raise(Redis::CannotConnectError, 'redis')

    marcar_nao_lida

    expect(response).to have_http_status(:success)
    expect(ConversaCanal::FilaDoEmailLido.new(inbox.id).pendente?).to be(false)
    expect(conversation.reload.agent_last_seen_at).to eq(ultima.created_at - 1.second)
    expect(ConversaCanal::EmailLido.nao_lida_pendente?(ultima.id)).to be(false)
  end

  it 'mesmo throttle do Chatwoot: sem não lidas e lido há menos de 1 h, abrir não regrava o lido' do
    conversation.update!(agent_last_seen_at: agora - 10.minutes, assignee_last_seen_at: agora - 10.minutes)

    expect { abrir(read_receipt: true) }.not_to(change { conversation.reload.agent_last_seen_at })
  end

  it 'com não lidas, o responsável grava agent_last_seen_at e assignee_last_seen_at, como no Chatwoot' do
    conversation.update!(assignee: agent)

    abrir(read_receipt: true)

    expect(conversation.reload.agent_last_seen_at).to be_within(1.second).of(agora)
    expect(conversation.assignee_last_seen_at).to eq(conversation.agent_last_seen_at)
  end

  it 'ciclo: cliente marca não lido no Gmail -> volta a não lida aqui, sem job de volta e sem laço' do
    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }
    importar

    servidor[21][:seen] = false
    perform_enqueued_jobs(only: job) { importar }

    expect(conversation.reload.agent_last_seen_at).to eq(ultima.created_at - 1.second)
    expect(conversation.assignee_last_seen_at).to eq(ultima.created_at - 1.second)
    expect(imap).to have_received(:uid_store).once
    2.times { importar }
    expect(lido_aqui?).to be(false)
    expect(servidor[21][:seen]).to be(false)

    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }
    expect(servidor[21][:seen]).to be(true)
  end

  it 'ciclo: cliente lê no Gmail -> lida aqui -> o painel não reescreve' do
    importar
    servidor[21][:seen] = true

    importar

    expect(lido_aqui?).to be(true)
    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }
    expect(imap).not_to have_received(:uid_store)
  end

  it 'flag desligada: o lido do painel continua pelo Chatwoot e nada é enfileirado' do
    account.disable_features!(ConversaCanal::EmailLido::FLAG)
    allow(ConversaCanal::LidoDaConversa).to receive(:new).and_call_original

    abrir(read_receipt: true)
    expect(response).to have_http_status(:success)
    expect(lido_aqui?).to be(true)

    marcar_nao_lida
    expect(conversation.reload.agent_last_seen_at).to eq(ultima.created_at - 1.second)
    expect(ConversaCanal::LidoDaConversa).not_to have_received(:new)
    expect(job).not_to have_been_enqueued
    expect(ConversaCanal::EmailLido.count).to eq(0)
  end

  it 'caixa só com encaminhamento (sem IMAP): nada enfileirado' do
    channel.update!(imap_enabled: false)

    abrir(read_receipt: true)
    marcar_nao_lida

    expect(job).not_to have_been_enqueued
  end

  it 'falha ao preparar o lido no servidor não derruba a leitura no painel' do
    allow(ConversaCanal::EmailLidoNoServidor).to receive(:new).and_raise(StandardError, 'quebrou')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    abrir(read_receipt: true)
    expect(response).to have_http_status(:success)
    expect(lido_aqui?).to be(true)

    marcar_nao_lida
    expect(response).to have_http_status(:success)
    expect(conversation.reload.agent_last_seen_at).to eq(ultima.created_at - 1.second)
    # Só a primeira falha da caixa na hora vai ao rastreador (ConversaCanal::FalhaDoEmailLido).
    expect(tracker).to have_received(:capture_exception).once
  end

  it 'falha do IMAP no job não derruba a leitura no painel' do
    allow(imap).to receive(:uid_store).and_raise(IOError, 'caiu')

    perform_enqueued_jobs(only: job) { abrir(read_receipt: true) }

    expect(response).to have_http_status(:success)
    expect(lido_aqui?).to be(true)
  end
end
