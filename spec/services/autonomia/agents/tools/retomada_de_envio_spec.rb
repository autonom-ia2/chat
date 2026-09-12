require 'rails_helper'

# A RETOMADA DO ENVIO PENDENTE PELO VARREDOR (rodada 9 da entrega 11). O `reap_stale_runs_job_spec`
# prova o desfecho pelo job inteiro; o que fica AQUI é o que o desfecho não mostra — a ORDEM: a
# conversa é travada ANTES de o `SendReplyJob` entrar na fila, e a mensagem é RELIDA sob o lock (um
# objeto velho, com a marca, não reenvia o que o banco já não tem). Sem estas duas guardas, a retomada
# "sob o lock" seria só uma frase no comentário.
RSpec.describe Autonomia::Agents::Tools::RetomadaDeEnvio do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                     scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
                              .tap { |r| r.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now) }
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  # -> a mensagem marcada pela primeira tentativa do publicador (fila recusando o envio), com a fila já
  # de volta — LIDA DO BANCO, como o varredor a lê (`marcadas`): a instância do `let` carrega o
  # `display_id` que o banco atribui, e `lock!` recusa registro com mudança não persistida.
  def mensagem_pendente(execucao = run, texto = 'cotação pronta')
    fila_recusa_o_envio
    expect(Autonomia::Agents::Tools::AsyncPublisher.new(run: execucao).publish(texto)).to be_blocked
    fila_volta
    Message.find(conversation.messages.where(sender_type: 'AgentBot').sole.id).tap do |mensagem|
      expect(Autonomia::Agents::Tools::PendenciaDeEnvio).to be_pendente(mensagem)
    end
  end

  it 'trava a conversa antes de por o reenvio na fila' do
    # Arrange
    mensagem = mensagem_pendente
    eventos = []
    sql = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      eventos << :trava if payload[:sql].to_s.include?('FOR UPDATE')
    end
    fila = ActiveSupport::Notifications.subscribe('enqueue.active_job') do |*, payload|
      eventos << :fila if payload[:job].is_a?(SendReplyJob)
    end

    # Act
    described_class.new(run: run).recuperar(mensagem)

    # Assert — o lock, e só então o job
    expect(eventos).to eq(%i[trava fila])
    expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
  ensure
    ActiveSupport::Notifications.unsubscribe(sql) if sql
    ActiveSupport::Notifications.unsubscribe(fila) if fila
  end

  it 'rele a mensagem sob o lock: o objeto velho com a marca nao reenvia o que o banco ja nao tem' do
    # Arrange — o varredor leu a mensagem marcada; antes de ele travar, outro processo resolveu a pendência
    mensagem = mensagem_pendente
    velha = Message.find(mensagem.id)
    Autonomia::Agents::Tools::PendenciaDeEnvio.limpar(mensagem, contexto: 'outro processo')

    # Act
    resolvido = described_class.new(run: run).recuperar(velha)

    # Assert
    expect(resolvido).to be(true)
    expect(SendReplyJob).not_to have_been_enqueued
  end

  # A RETOMADA TAMBÉM PERGUNTA À FERRAMENTA (rodada 4 da entrega 8, P1 do Codex; mutação MR).
  #
  # A mensagem existir no painel NÃO é ter chegado ao cliente: reenfileirar o `SendReplyJob` dela é
  # entregar o arquivo AGORA. Se a cotação de origem foi refeita nesse meio-tempo, a proposta é a dos
  # preços que o cliente descartou — e o desvio R6 da rodada 3 ("a mensagem já existe, quem decide lá
  # é o resto") deixava esse reenvio passar. Quem identifica a entrega é o TOKEN da mensagem, e a
  # pendência é RESOLVIDA (`abandonar`), não deixada para o varredor reencontrar a cada 10 min.
  describe 'a entrega que a propria ferramenta ja nao publicaria' do
    let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
    let(:proposta) { Autonomia::Agents::Tools::Native::InsuranceProposal }
    # `http`: a forma de arquivo recusa a URL, a proposta vai como LINK EM TEXTO — e é esse texto,
    # com o mesmo token, que a mensagem pendente carrega (o caminho da reserva, já provado na
    # ferramenta). Assim a pendência é montada sem download nem anexo.
    let(:url) { 'http://arquivos.exemplo.test/proposta-8.pdf' }
    let(:reserva) { "Proposta da Porto:\n#{url}" }

    # A cotação de origem (com preço e mapa de nomes) e a execução da PROPOSTA que saiu dela, com a
    # URL já gerada no handle — o estado em que o publicador a entregou.
    def proposta_gerada_da_cotacao
      origem = Autonomia::Agents::ToolRun.create!(
        account: account, agent: agent, conversation_id: conversation.id, slug: cotacao.slug, status: 'done',
        execution_key: SecureRandom.uuid, arguments: { 'produto' => 'auto' },
        handle: { 'quote_id' => 'q1', 'produto' => 'auto', cotacao::DELIVERED_KEY => ['8'],
                  cotacao::NOMES_KEY => { '8' => 'Porto' } }
      )
      execucao_da_proposta(origem)
    end

    def execucao_da_proposta(origem)
      run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: proposta.slug,
                                             arguments: { 'seguradoras' => ['Porto'], proposta::ORIGEM => origem.id },
                                             scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
      run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
      run.update!(handle: { 'sufixo' => 'placa ABC1D23',
                            proposta::GERADAS => [{ 'code' => '8', 'name' => 'Porto', 'url' => url }] })
      run
    end

    def cotacao_nova
      Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, arguments: { 'produto' => 'auto' },
                                       scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
                                .tap { |nova| nova.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now) }
    end

    it 'abandona a pendencia em vez de reenviar a proposta de uma cotacao ja refeita' do
      # Arrange — a proposta virou mensagem, o envio ficou pendente, e só então o cliente mandou refazer
      execucao = proposta_gerada_da_cotacao
      mensagem = mensagem_pendente(execucao, reserva)
      cotacao_nova

      # Act
      resolvido = described_class.new(run: execucao).recuperar(mensagem)

      # Assert — nada vai ao cliente, e a pendência não fica para o varredor achar de novo
      expect(resolvido).to be(true)
      expect(SendReplyJob).not_to have_been_enqueued
      expect(Autonomia::Agents::Tools::PendenciaDeEnvio).not_to be_marcada(Message.find(mensagem.id))
    end

    # O QUE `entrega_do_token` LEVANTA NÃO VIRA ENTREGA (rodada 5, P3). Ao contrário de `publicavel?`,
    # este hook NÃO tem `rescue` — e o comentário de `AutorizacaoDaExecucao` afirmava que a proposta
    # tratava as exceções dela "dentro do próprio hook, e não chega aqui": verdade só para o outro. A
    # invariante verdadeira, agora escrita, é a mesma dos dois lados: o que não se consegue conferir
    # NÃO SAI. Um `rescue` devolvendo nil aqui seria o CONTRÁRIO da decisão do dinheiro — nil
    # significa "não reconheço esta entrega", e não barraria nada.
    it 'o hook que levanta nao reenvia a proposta: nada vai ao cliente, e a marca fica' do
      # Arrange — a proposta virou mensagem, o envio ficou pendente, e a conferência do token quebra
      # A conferência quebra DENTRO do hook de verdade — é ele que monta o token de cada proposta
      # gerada. Um dublê que substituísse `entrega_do_token` provaria só o dublê: um `rescue`
      # engolindo a exceção lá dentro passaria despercebido, que é exatamente o risco desta correção
      # (medido por mutação: com o dublê, pôr o `rescue` no hook não derrubava nada).
      execucao = proposta_gerada_da_cotacao
      mensagem = mensagem_pendente(execucao, reserva)
      allow(execucao).to receive(:delivery_token).and_raise(ActiveRecord::StatementInvalid, 'banco fora')

      # Act / Assert — sobe para quem chamou (o varredor registra e segue), e nada é reenviado
      expect { described_class.new(run: execucao).recuperar(mensagem) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(SendReplyJob).not_to have_been_enqueued
      expect(Autonomia::Agents::Tools::PendenciaDeEnvio).to be_marcada(Message.find(mensagem.id))
    end

    it 'reenvia normalmente enquanto a cotacao de origem continua sendo a ultima' do
      execucao = proposta_gerada_da_cotacao
      mensagem = mensagem_pendente(execucao, reserva)

      expect(described_class.new(run: execucao).recuperar(mensagem)).to be(true)
      expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
    end
  end
end
