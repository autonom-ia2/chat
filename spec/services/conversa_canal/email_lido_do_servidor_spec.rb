require 'rails_helper'

# #1870 — servidor do cliente -> painel: a importação de cada minuto traz o \Seen dos e-mails já importados.
RSpec.describe ConversaCanal::EmailLidoDoServidor do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :imap_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:imap) { instance_double(Net::IMAP) }
  let(:agora) { Time.zone.parse('2020-10-26 10:00') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, agent_last_seen_at: agora - 3.hours) }
  let(:linhas) { ConversaCanal::EmailLido }
  # Servidor falso: { uid => { message_id:, seen: } }. A busca da janela devolve todos; UID FETCH devolve o cabeçalho.
  let(:servidor) { {} }

  def recebida(source_id, criada_em, conversa: conversation)
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming,
                     source_id: source_id, created_at: criada_em)
  end

  def no_servidor(uid, message_id, seen:)
    servidor[uid] = { message_id: message_id, seen: seen }
  end

  def flags_de(seen)
    seen ? [:Seen] : []
  end

  def estado_de(seq)
    uid = servidor.keys[seq - 1]
    Net::IMAP::FetchData.new(seq, 'UID' => uid, 'FLAGS' => flags_de(servidor[uid][:seen]))
  end

  def cabecalho_de(uid)
    Net::IMAP::FetchData.new(uid, 'UID' => uid, 'BODY[HEADER.FIELDS (MESSAGE-ID)]' => "Message-ID: <#{servidor[uid][:message_id]}>\r\n\r\n")
  end

  def simular_servidor
    allow(imap).to receive(:fetch).with(anything, described_class::ESTADO) { |seqs, _| seqs.map { |seq| estado_de(seq) } }
    allow(imap).to receive(:uid_fetch).with(anything, [ConversaCanal::MessageIdsDoServidor::PEDIDO]) do |uids, _|
      uids.map { |uid| cabecalho_de(uid) }
    end
  end

  def importar(servico = Imap::FetchEmailService.new(channel: channel))
    travel_to(agora) { servico.perform }
  end

  def limpar_cache
    %w[777 999 sem].each { |validade| Redis::Alfred.delete("conversa_canal:email_lido:message_ids:#{inbox.id}:#{validade}") }
  end

  # Primeira sincronização da caixa: o ponto de partida (só grava o estado).
  def ativar
    importar
  end

  after { limpar_cache }

  before do
    account.enable_features!(ConversaCanal::EmailLido::FLAG)
    limpar_cache
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:authenticate)
    allow(imap).to receive(:select).with('INBOX')
    allow(imap).to receive(:logout)
    allow(imap).to receive(:responses).with('UIDVALIDITY').and_yield([777])
    # A importação em si (janela de 1 dia) não acha e-mail novo.
    allow(imap).to receive(:search).with(%w[SINCE 25-Oct-2020]).and_return([])
    allow(imap).to receive(:search).with(%w[SINCE 24-Oct-2020]) { (1..servidor.size).to_a }
    simular_servidor
  end

  context 'with password login (Imap::FetchEmailService)' do
    it 'ativação: grava UID, UIDVALIDITY e \Seen, sem mudar o lido de nenhuma conversa' do
      outra = create(:conversation, account: account, inbox: inbox, agent_last_seen_at: agora - 3.hours)
      ultima = recebida('ultimo@cliente.com', agora - 1.hour)
      da_outra = recebida('outra@cliente.com', agora - 1.hour, conversa: outra)
      no_servidor(11, 'ultimo@cliente.com', seen: true)
      no_servidor(12, 'outra@cliente.com', seen: true)

      expect { ativar }.not_to(change { [conversation.reload.agent_last_seen_at, outra.reload.agent_last_seen_at] })
      expect(linhas.find_by!(message_id: ultima.id).slice(:uid, :uidvalidity, :seen_no_servidor))
        .to eq('uid' => 11, 'uidvalidity' => 777, 'seen_no_servidor' => true)
      expect(linhas.find_by!(message_id: da_outra.id).seen_no_servidor).to be(true)
      expect { importar }.not_to(change { conversation.reload.agent_last_seen_at })
    end

    it 'passagem de não lido para lido no último recebido: a conversa fica lida, para todos, com os contadores' do
      ultima = recebida('ultimo@cliente.com', agora - 1.hour)
      no_servidor(11, 'ultimo@cliente.com', seen: false)
      ativar
      allow(Conversations::UnreadCounts::Notifier).to receive(:new).and_call_original

      servidor[11][:seen] = true
      importar

      expect(conversation.reload.agent_last_seen_at).to eq(agora)
      expect(conversation.assignee_last_seen_at).to eq(agora)
      expect(Conversations::UnreadCounts::Notifier).to have_received(:new).with(conversation)
      expect(linhas.find_by!(message_id: ultima.id).seen_no_servidor).to be(true)
      expect(imap).to have_received(:logout).twice
    end

    it 'regra 1: lido só o primeiro e chegou outro, a conversa continua não lida' do
      recebida('primeiro@cliente.com', agora - 2.hours)
      recebida('ultimo@cliente.com', agora - 1.hour)
      no_servidor(10, 'primeiro@cliente.com', seen: false)
      no_servidor(11, 'ultimo@cliente.com', seen: false)
      ativar

      servidor[10][:seen] = true
      expect { importar }.not_to(change { conversation.reload.agent_last_seen_at })
    end

    it 'passagem de lido para não lido no último (cliente marcou não lido): volta a não lida aqui, sem job e sem laço' do
      ultima = recebida('ultimo@cliente.com', agora - 1.hour)
      conversation.update!(agent_last_seen_at: agora - 10.minutes, assignee_last_seen_at: agora - 10.minutes)
      no_servidor(11, 'ultimo@cliente.com', seen: true)
      ativar

      servidor[11][:seen] = false
      importar

      expect(conversation.reload.agent_last_seen_at).to eq(ultima.created_at - 1.second)
      expect(conversation.assignee_last_seen_at).to eq(ultima.created_at - 1.second)
      expect(ConversaCanal::EmailLidoNoServidorJob).not_to have_been_enqueued
      expect(linhas.find_by!(message_id: ultima.id).desmarcado_no_servidor_em).to eq(agora)
      expect { importar }.not_to(change { conversation.reload.agent_last_seen_at })
    end

    it 'não lido num e-mail que não é o último: a conversa não muda' do
      recebida('primeiro@cliente.com', agora - 2.hours)
      recebida('ultimo@cliente.com', agora - 1.hour)
      conversation.update!(agent_last_seen_at: agora - 10.minutes)
      no_servidor(10, 'primeiro@cliente.com', seen: true)
      no_servidor(11, 'ultimo@cliente.com', seen: true)
      ativar

      servidor[10][:seen] = false
      expect { importar }.not_to(change { conversation.reload.agent_last_seen_at })
    end

    it 'não desfaz o "marcar não lida" daqui: servidor que continua \Seen não remarca como lida' do
      ultima = recebida('ultimo@cliente.com', agora - 1.hour)
      no_servidor(11, 'ultimo@cliente.com', seen: true)
      ativar
      conversation.update!(agent_last_seen_at: ultima.created_at - 1.second)

      expect { importar }.not_to(change { conversation.reload.agent_last_seen_at })
    end

    it '"não lida" do painel ainda não escrita lá (marca pendente): a passagem para lido não muda a conversa' do
      ultima = recebida('ultimo@cliente.com', agora - 1.hour)
      no_servidor(11, 'ultimo@cliente.com', seen: false)
      ativar
      servidor[11][:seen] = true
      ConversaCanal::EmailLido.nao_lida_pendente!(ultima)

      expect { importar }.not_to(change { conversation.reload.agent_last_seen_at })
      ConversaCanal::EmailLido.nao_lida_resolvida!(ultima.id)
      expect { importar }.not_to(change { conversation.reload.agent_last_seen_at })
    ensure
      ConversaCanal::EmailLido.nao_lida_resolvida!(ultima.id)
    end

    it 'e-mail que chega depois do ponto de partida já lido conta como lido' do
      ativar
      ultima = recebida('novo@cliente.com', agora + 1.minute)
      no_servidor(15, 'novo@cliente.com', seen: true)

      travel_to(agora + 2.minutes) { Imap::FetchEmailService.new(channel: channel).perform }

      expect(conversation.reload.agent_last_seen_at).to be >= ultima.created_at
    end

    it 'custo: com UIDs conhecidos, só UID e FLAGS; o Message-ID só para UID novo' do
      recebida('ultimo@cliente.com', agora - 1.hour)
      no_servidor(11, 'ultimo@cliente.com', seen: false)
      ativar
      expect(imap).to have_received(:uid_fetch).with([11], anything).once

      servidor[11][:seen] = true
      importar

      expect(imap).to have_received(:uid_fetch).once
    end

    it 'custo: UID sem mensagem nossa (notificação, não importado) não tem o cabeçalho pedido de novo no minuto seguinte' do
      no_servidor(90, 'notificacao@chat2you.com', seen: false)
      ativar

      travel_to(agora + 1.minute) { Imap::FetchEmailService.new(channel: channel).perform }

      expect(imap).to have_received(:uid_fetch).with([90], anything).once
      expect(linhas.count).to eq(0)
    end

    it 'UIDVALIDITY ausente (nil): usa o UID gravado sem regravar a linha nem pedir o cabeçalho de novo' do
      allow(imap).to receive(:responses).with('UIDVALIDITY').and_yield([])
      ultima = recebida('ultimo@cliente.com', agora - 1.hour)
      no_servidor(11, 'ultimo@cliente.com', seen: false)
      ativar
      linha = linhas.find_by!(message_id: ultima.id)
      expect([linha.uid, linha.uidvalidity]).to eq([11, nil])

      travel_to(agora + 1.minute) { Imap::FetchEmailService.new(channel: channel).perform }

      expect(linha.reload.updated_at).to eq(linha.created_at)
      expect(imap).to have_received(:uid_fetch).once
    end

    it 'UIDVALIDITY nova: pede o Message-ID de novo, troca o UID e mantém a comparação do \Seen' do
      ultima = recebida('ultimo@cliente.com', agora - 1.hour)
      no_servidor(11, 'ultimo@cliente.com', seen: false)
      ativar
      allow(imap).to receive(:responses).with('UIDVALIDITY').and_yield([999])
      servidor.clear
      no_servidor(40, 'ultimo@cliente.com', seen: true)

      importar

      expect(linhas.find_by!(message_id: ultima.id).slice(:uid, :uidvalidity)).to eq('uid' => 40, 'uidvalidity' => 999)
      expect(conversation.reload.agent_last_seen_at).to eq(agora)
    end

    it 'caixa parada mais que RECOMECO: recomeça do zero, sem passagem em massa e sem apagar no lock' do
      ultima = recebida('ultimo@cliente.com', agora - 1.hour)
      no_servidor(11, 'ultimo@cliente.com', seen: false)
      ativar
      servidor[11][:seen] = true

      travel_to(agora + 2.hours) { Imap::FetchEmailService.new(channel: channel).perform }

      expect(conversation.reload.agent_last_seen_at).to eq(agora - 3.hours)
      linha = linhas.find_by!(message_id: ultima.id)
      expect([linha.seen_no_servidor, linha.sincronizado_em]).to eq([true, agora + 2.hours])
      expect(ConversaCanal::EmailLidoCaixa.find_by!(inbox_id: inbox.id).ponto_de_partida).to eq(agora + 2.hours)
    end

    it 'acumulado depois do recomeço ("confirmo o lido"): só e-mail importado depois do ponto novo e já lido conta' do
      outra = create(:conversation, account: account, inbox: inbox, agent_last_seen_at: agora - 3.hours)
      antiga = recebida('antigo@cliente.com', agora - 1.hour, conversa: outra)
      no_servidor(11, 'antigo@cliente.com', seen: false)
      ativar
      servidor[11][:seen] = true
      recomeco = agora + 2.hours
      travel_to(recomeco) { Imap::FetchEmailService.new(channel: channel).perform }
      do_acumulado = recebida('acumulado@cliente.com', recomeco + 1.minute)
      no_servidor(12, 'acumulado@cliente.com', seen: true)

      travel_to(recomeco + 2.minutes) { Imap::FetchEmailService.new(channel: channel).perform }

      expect(conversation.reload.agent_last_seen_at).to eq(recomeco + 2.minutes)
      expect(conversation.agent_last_seen_at).to be >= do_acumulado.created_at
      expect(outra.reload.agent_last_seen_at).to eq(agora - 3.hours)
      expect(linhas.find_by!(message_id: antiga.id).seen_no_servidor).to be(true)
    end

    it 'flag desligada: nada muda, nem a busca da janela de 2 dias' do
      account.disable_features!(ConversaCanal::EmailLido::FLAG)
      recebida('ultimo@cliente.com', agora - 1.hour)

      expect { importar }.not_to(change { conversation.reload.agent_last_seen_at })
      expect(imap).not_to have_received(:search).with(%w[SINCE 24-Oct-2020])
      expect(linhas.count).to eq(0)
    end
  end

  context 'with Google (OAuth)' do
    let(:channel) do
      create(:channel_email, :imap_email, account: account, provider: 'google', imap_password: '',
                                          provider_config: { 'access_token' => 'token-velho', 'refresh_token' => 'r',
                                                             'expires_on' => (agora + 1.hour).to_s })
    end

    it 'traz o \Seen pela mesma conexão XOAUTH2 da importação' do
      allow(Google::RefreshOauthTokenService).to receive(:new)
        .and_return(instance_double(Google::RefreshOauthTokenService, access_token: 'token'))
      ultima = recebida('ultimo@cliente.com', agora - 1.hour)
      no_servidor(11, 'ultimo@cliente.com', seen: false)
      importar(Imap::GoogleFetchEmailService.new(channel: channel))
      servidor[11][:seen] = true

      importar(Imap::GoogleFetchEmailService.new(channel: channel))

      expect(imap).to have_received(:authenticate).with('XOAUTH2', channel.imap_login, 'token').twice
      expect(linhas.find_by!(message_id: ultima.id).seen_no_servidor).to be(true)
      expect(conversation.reload.agent_last_seen_at).to eq(agora)
    end
  end

  it 'caixa só com encaminhamento (sem IMAP) não sincroniza' do
    channel.update!(imap_enabled: false)

    expect(ConversaCanal::EmailLido.sincroniza?(inbox)).to be(false)
  end
end
