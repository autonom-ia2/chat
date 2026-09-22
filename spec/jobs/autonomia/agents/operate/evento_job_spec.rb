require 'rails_helper'

# O TURNO DA LIA ACIONADO POR UM EVENTO DA COTAÇÃO (PR C). Cada exemplo cobre um modo de falha do desenho:
# falar com frase pronta, falar duas vezes, falar antes do PDF ou no meio da frase do turno, abrir cotação que a
# pessoa não pediu, calar quando a IA falha, falar por cima de quem está atendendo.
RSpec.describe Autonomia::Agents::Operate::EventoJob, type: :job do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:evento) { Autonomia::Agents::Tools::Evento }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    register_async_tool(build_async_tool)
    lia_responde('Terminei a cotação e te mandei o comparativo aqui em cima.')
  end

  def execucao(expected_chunks: 0, origem: nil)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id,
                                                    origin_message_id: origem })
    run.promote!(expected_chunks: expected_chunks, notify_customer: false, expires_at: 3.minutes.from_now)
    run
  end

  def mensagens = conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
  def publicas = mensagens.where(private: false)
  def privadas = mensagens.where(private: true)

  def reagendados
    enqueued_jobs.select { |job| job[:job] == described_class }.map { |job| job[:args] }
  end

  describe 'a fala' do
    it 'posta a fala do modelo, uma mensagem publica marcada com o evento, sem texto nosso' do
      run = execucao

      described_class.new.perform(run.id, 'concluida')

      mensagem = publicas.sole
      expect(mensagem.content).to eq('Terminei a cotação e te mandei o comparativo aqui em cima.')
      expect(mensagem.content_attributes).to include(evento::CHAVE => "#{run.id}:concluida")
      expect(mensagem.content_attributes).not_to have_key('autonomia_reply_to_message_id')
      expect(privadas).to be_empty
    end

    # A NOTA DO SISTEMA é o que o modelo recebe no lugar da mensagem do cliente: diz que é do sistema, o que
    # aconteceu e os fatos da ferramenta.
    it 'da ao modelo a nota do sistema com a descricao e os fatos da ferramenta' do
      run = execucao

      described_class.new.perform(run.id, 'falta_dado')

      expect(queries_da_lia.sole).to include('AVISO DO SISTEMA', 'Isto não é mensagem da pessoa', 'fatos do dublê: falta_dado')
    end

    # A LIA NÃO ABRE COTAÇÃO NO TURNO DE UM AVISO: o contexto de entrega carrega o evento, e a ferramenta assíncrona
    # recusa (`turno_de_evento`, registrada em `recusa_registro_spec`).
    it 'o turno roda com o contexto de entrega do evento, que recusa cotacao nova' do
      run = execucao
      contexto = nil
      allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
        contexto = kwargs[:delivery]
        instance_double(Autonomia::Agents::Answerer, answer: resposta_da_lia('ok'))
      end

      described_class.new.perform(run.id, 'concluida')

      expect(contexto).to be_turno_de_evento
      tool = Autonomia::Agents::Tools::Bound.new(agent: agent, native: build_async_tool)
      recusa = tool.execute({ 'name' => 'consultar_cotacao', 'arguments' => '{}' }, delivery: contexto)
      expect(JSON.parse(recusa)).to eq('error' => 'turno_de_evento')
      expect(Autonomia::Agents::ToolRun.where.not(id: run.id)).to be_empty
    end
  end

  # MENSAGEM ÚNICA, SEM A PORTA DE ENGAJAMENTO: a entrega humanizada depende de uma mensagem de origem, que o turno
  # de evento não tem; e a porta de engajamento é para quem começa a conversa, não para a continuação dela.
  describe 'o caminho da entrega' do
    it 'com a entrega humanizada ligada, sai uma mensagem so, sem cadeia de pedacos' do
      allow(Autonomia::Agents::Config).to receive(:humanize_delivery_enabled?).and_return(true)
      run = execucao

      described_class.new.perform(run.id, 'concluida')

      expect(publicas.count).to eq(1)
      expect(Autonomia::Agents::Operate::ChunkedDeliveryJob).not_to have_been_enqueued
    end

    it 'a porta de engajamento nao se aplica: fora do horario, o turno do evento fala' do
      agent.update!(config: agent.config.merge('response_window' => 'business_hours'))
      allow_any_instance_of(Autonomia::Agents::Operate::EngagementGate).to receive(:blocked_reason).and_return('schedule') # rubocop:disable RSpec/AnyInstance
      run = execucao

      described_class.new.perform(run.id, 'concluida')

      expect(publicas.count).to eq(1)
      expect(Autonomia::Agents::AgentEvent.where(event_type: 'skipped_schedule')).to be_empty
    end
  end

  describe 'idempotencia' do
    it 'o mesmo evento rodando duas vezes (retry do job) posta uma mensagem so' do
      run = execucao

      2.times { described_class.new.perform(run.id, 'falhou') }

      expect(publicas.count).to eq(1)
    end

    it 'o evento disparado duas vezes (duas portas) enfileira um turno so' do
      run = execucao

      expect(evento.disparar(run, 'falhou')).to be(true)
      expect(evento.disparar(run.reload, 'concluida')).to be(false)

      expect(eventos_disparados(run)).to eq(['falhou'])
    end

    it 'a mensagem do evento ja na conversa (a IA respondeu e o job morreu depois) nao chama o modelo de novo' do
      run = execucao
      described_class.new.perform(run.id, 'concluida')
      allow(Autonomia::Agents::Answerer).to receive(:new).and_raise('o modelo nao devia ser chamado')

      expect { described_class.new.perform(run.id, 'concluida') }.not_to raise_error
      expect(publicas.count).to eq(1)
    end
  end

  describe 'a falha do turno' do
    it 'IA falhou: nova tentativa, com espera, e nada postado' do
      lia_responde(nil)
      run = execucao

      described_class.new.perform(run.id, 'falhou')

      expect(mensagens).to be_empty
      expect(reagendados).to eq([[run.id, 'falhou', 0, 1, []]])
      espera = enqueued_jobs.find { |job| job[:job] == described_class }[:at]
      expect(espera).to be_within(2).of(described_class::ESPERA_DA_NOVA_TENTATIVA.from_now.to_f)
    end

    it 'resposta vazia: nova tentativa, nada postado' do
      lia_responde('   ')
      run = execucao

      described_class.new.perform(run.id, 'concluida')

      expect(mensagens).to be_empty
      expect(reagendados).to eq([[run.id, 'concluida', 0, 1, []]])
    end

    # O SINAL DE SILÊNCIO É DECISÃO, não falha (revisão da chat#588): sem nova tentativa e sem handoff, só a nota.
    it 'sinal de silencio: nada publico, so a nota privada, sem nova tentativa nem handoff' do
      lia_responde('conversation_closed_for_now')
      conversation.update!(ai_assignee: agent_bot, status: :pending)
      run = execucao

      described_class.new.perform(run.id, 'concluida')

      expect(publicas).to be_empty
      expect(privadas.sole.content).to include('decidiu não falar')
      expect(reagendados).to be_empty
      expect(conversation.reload.status).to eq('pending')
    end

    # FALHOU DE NOVO: o atendente é avisado pela notificação do Chatwoot (`bot_handoff!`, sob o lock, com o
    # espelho no comando) e por uma NOTA PRIVADA com o evento. Nenhuma mensagem pública de sistema.
    it 'falhou de novo: handoff, nota privada com o evento, e nenhuma mensagem publica' do
      lia_responde(nil)
      conversation.update!(ai_assignee: agent_bot, status: :pending)
      run = execucao
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      described_class.new.perform(run.id, 'falhou', 0, 1)

      expect(publicas).to be_empty
      nota = privadas.sole
      expect(nota.content).to include("execução #{run.id}", 'fatos do dublê: falhou', 'passada para a equipe')
      expect(nota.content_attributes).to include(evento::CHAVE => "#{run.id}:falhou")
      expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(Events::Types::CONVERSATION_BOT_HANDOFF, any_args)
      expect(Autonomia::Agents::AgentEvent.handed_off.where(agent: agent).sole.handoff_reason).to eq('ai_unavailable')
      expect(reagendados).to be_empty
    end

    it 'o handoff repetido (retry do job) nao duplica a nota nem o evento' do
      lia_responde(nil)
      conversation.update!(ai_assignee: agent_bot, status: :pending)
      run = execucao

      2.times { described_class.new.perform(run.id, 'falhou', 0, 1) }

      expect(privadas.count).to eq(1)
      expect(Autonomia::Agents::AgentEvent.handed_off.count).to eq(1)
    end
  end

  describe 'quem esta no comando' do
    let(:atendente) { create(:user, account: account, role: :agent) }

    it 'com humano na conversa, o modelo nao roda: so a nota privada' do
      conversation.update!(assignee: atendente)
      run = execucao
      allow(Autonomia::Agents::Answerer).to receive(:new).and_raise('o modelo nao devia ser chamado')

      described_class.new.perform(run.id, 'concluida')

      expect(publicas).to be_empty
      expect(privadas.sole.content).to include('a conversa está com um atendente')
    end

    it 'com o agente desligado, so a nota privada' do
      run = execucao
      agent.update!(enabled: false)

      described_class.new.perform(run.id, 'falhou')

      expect(publicas).to be_empty
      expect(privadas.count).to eq(1)
    end

    it 'humano que assume durante a chamada de IA: nada publico, e a nota privada' do
      run = execucao
      allow(Autonomia::Agents::Answerer).to receive(:new) do
        conversation.update!(assignee: atendente)
        instance_double(Autonomia::Agents::Answerer, answer: resposta_da_lia('fala que chegou tarde'))
      end

      described_class.new.perform(run.id, 'concluida')

      expect(publicas).to be_empty
      expect(privadas.count).to eq(1)
    end

    it 'a execucao morta (supersedida por um pedido novo) nao aciona turno nenhum' do
      run = execucao
      run.update_columns(status: 'superseded') # rubocop:disable Rails/SkipsModelValidations

      described_class.new.perform(run.id, 'concluida')

      expect(mensagens).to be_empty
    end
  end

  describe 'a ordem' do
    it 'espera a cadeia humanizada do turno que abriu a execucao' do
      origem = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
      run = execucao(expected_chunks: 1, origem: origem.id)

      described_class.new.perform(run.id, 'cotacao_comecou')

      expect(mensagens).to be_empty
      expect(reagendados).to eq([[run.id, 'cotacao_comecou', 1, 0, []]])
    end

    it 'o fecho espera a palavra do comeco' do
      run = execucao
      evento.disparar(run, 'cotacao_comecou')

      described_class.new.perform(run.id, 'falhou')
      expect(publicas).to be_empty

      described_class.new.perform(run.id, 'cotacao_comecou')
      described_class.new.perform(run.id, 'falhou')
      expect(publicas.map { |m| m.content_attributes[evento::CHAVE] }).to eq(["#{run.id}:cotacao_comecou", "#{run.id}:falhou"])
    end

    # A CONCLUSÃO SAI DEPOIS DO PDF: o arquivo aceito (lista do aceite, ou o que veio em `depois_de`) que ainda
    # não é mensagem segura o turno.
    it 'a conclusao espera o arquivo aceito virar mensagem' do
      run = execucao
      token = run.delivery_token('arquivo:https://x.test/c.pdf')
      run.registrar_entrega_aceita!(token)

      described_class.new.perform(run.id, 'concluida')
      expect(mensagens).to be_empty

      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_bot,
                       content: nil, content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE => token })
      described_class.new.perform(run.id, 'concluida', 1)
      expect(publicas.last.content_attributes[evento::CHAVE]).to eq("#{run.id}:concluida")
    end

    # NO TETO, SEM O ARQUIVO, a conclusão fala como resultado guardado: a Lia não afirma o PDF que não chegou
    # (revisão da chat#588).
    it 'o arquivo de depois_de tambem segura, e no teto o turno fala sem ele, como resultado guardado' do
      run = execucao
      token = run.delivery_token('arquivo:https://x.test/d.pdf')

      described_class.new.perform(run.id, 'concluida', 0, 0, [token])
      expect(mensagens).to be_empty

      described_class.new.perform(run.id, 'concluida', Autonomia::Agents::Tools::AsyncConfig::MAX_DEPENDENCY_DEFERRALS, 0, [token])
      expect(publicas.sole.content_attributes[evento::CHAVE]).to eq("#{run.id}:valores_guardados")
      expect(queries_da_lia.last).to include('fatos do dublê: valores_guardados')
    end

    it 'o retry da conclusao que saiu sem o arquivo nao fala de novo quando o arquivo chega' do
      run = execucao
      token = run.delivery_token('arquivo:https://x.test/g.pdf')
      described_class.new.perform(run.id, 'concluida', Autonomia::Agents::Tools::AsyncConfig::MAX_DEPENDENCY_DEFERRALS, 0, [token])
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_bot,
                       content: nil, content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE => token })

      described_class.new.perform(run.id, 'concluida', 0, 0, [token])

      expect(publicas.where.not(content: nil).count).to eq(1)
    end

    # O "ESTOU CUIDANDO" QUE ATRASOU não sai depois do resultado (revisão da chat#588).
    it 'o comeco nao fala depois que o desfecho ja falou' do
      run = execucao
      evento.disparar(run, 'cotacao_comecou')
      evento.disparar(run.reload, 'falhou')
      described_class.new.perform(run.id, 'falhou', Autonomia::Agents::Tools::AsyncConfig::MAX_DEPENDENCY_DEFERRALS)

      described_class.new.perform(run.id, 'cotacao_comecou')

      expect(publicas.map { |m| m.content_attributes[evento::CHAVE] }).to eq(["#{run.id}:falhou"])
    end

    it 'o fecho nao espera um comeco que ja foi superado por arquivo na conversa' do
      run = execucao
      evento.disparar(run, 'cotacao_comecou')
      evento.disparar(run.reload, 'concluida')
      token = run.delivery_token('arquivo:https://x.test/f.pdf')
      run.registrar_entrega_aceita!(token)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_bot,
                       content: nil, content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE => token })

      described_class.new.perform(run.id, 'concluida')

      expect(publicas.where.not(content: nil).sole.content_attributes[evento::CHAVE]).to eq("#{run.id}:concluida")
    end

    it 'o comeco nao fala depois que um arquivo aceito ja chegou a conversa' do
      run = execucao
      token = run.delivery_token('arquivo:https://x.test/e.pdf')
      run.registrar_entrega_aceita!(token)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_bot,
                       content: nil, content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE => token })

      described_class.new.perform(run.id, 'cotacao_comecou')

      expect(publicas.where('content_attributes::text LIKE ?', "%#{evento::CHAVE}%")).to be_empty
    end
  end
end
