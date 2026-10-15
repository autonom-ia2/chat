require 'rails_helper'

# "Um turno, uma ordem" (#1606), pontos 3 e 4 e cenários 10, 11, 12, 15, 16 e 17 da bateria: a guarda do claim, a
# devolução para o responsável do funil e o que NÃO pode mudar (porta n8n, conta fora da Fase 2, Testar e Copiloto,
# telemetria sem conteúdo). Os leitores do Multifunnel são dublados pelo adaptador.
RSpec.describe Autonomia::Agents::QuemResponde, :um_turno do
  include_context 'with crm responsible agent'

  let(:pessoa) { create(:user, account: account, role: :agent) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    clear_enqueued_jobs
  end

  def robo_posta(robo, conversa = conversation)
    create(:message, account: conversa.account, conversation: conversa, inbox: conversa.inbox, message_type: :outgoing,
                     sender: robo, content: 'resposta do robô')
  end

  def desatribuir(conversa = conversation)
    Conversations::AssignmentService.new(conversation: conversa, assignee_id: nil).perform
    conversa.reload
  end

  describe 'cenário 10: a porta posta atrasada enquanto a área é dona' do
    before { conversation.update!(ai_assignee: espelho_area) }

    it 'o claim não troca o ai_assignee e deixa o rastro claim_barrado' do
      linhas = linhas_do_log { robo_posta(porta) }

      expect(conversation.reload.ai_assignee).to eq(espelho_area)
      expect(linhas.grep(/\[autonomia\]\[turno\] claim_barrado conv=#{conversation.id} dono=#{espelho_area.id} robo=#{porta.id}/).size)
        .to eq(1)
    end

    it 'conversa pendente vira aberta, com a área ainda dona' do
      conversation.update_columns(status: Conversation.statuses[:pending]) # rubocop:disable Rails/SkipsModelValidations

      robo_posta(porta)

      expect(conversation.reload).to have_attributes(status: 'open', ai_assignee: espelho_area)
    end

    it 'área parada não segura a conversa: a porta assume, como hoje' do
      area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations

      robo_posta(porta)

      expect(conversation.reload.ai_assignee).to eq(porta)
    end
  end

  describe 'cenário 11: desatribuir a pessoa' do
    before { conversation.update!(assignee: pessoa) }

    it 'com responsável no funil do card, a conversa vai para a área' do
      contrato!(robo: espelho_area)

      expect(desatribuir.ai_assignee).to eq(espelho_area)
    end

    it 'sem responsável, vai para a porta' do
      expect(desatribuir.ai_assignee).to eq(porta)
    end

    it 'robô de outra conta vindo do leitor é ignorado: porta' do
      contrato!(robo: create(:agent_bot, account: create(:account)))

      expect(desatribuir.ai_assignee).to eq(porta)
    end

    it 'robô da conta sem vínculo ativo NESTA caixa é ignorado: porta' do
      outra_caixa = create(:inbox, account: account)
      Autonomia::Agents::Operate::InboxConnector.new(agent: criar_agente('Porta de outra caixa'), inbox: outra_caixa).perform(connect: true)
      espelho_de_outra_caixa = Autonomia::Agents::Areas.vincular!(agent: criar_agente('Área de outra caixa'), inbox: outra_caixa)
                                                       .agent_bot
      contrato!(robo: espelho_de_outra_caixa)

      expect(desatribuir.ai_assignee).to eq(porta)
    end

    it 'espelho de vínculo removido desta caixa é ignorado: porta' do
      contrato!(robo: espelho_area)
      area_sumiu!

      expect(desatribuir.ai_assignee).to eq(porta)
    end
  end

  # A porta n8n (Placement): um robô externo, com webhook, numa caixa sem vínculo nosso. Mesmo com a Fase 2 ligada e o
  # CRM dizendo "espere o assunto", nada do turno muda.
  describe 'cenário 12: caixa n8n idêntica ao main' do
    let(:caixa_n8n) { create(:inbox, account: account) }
    let(:n8n) { create(:agent_bot, account: account, outgoing_url: 'https://n8n.example.test/webhook') }
    let(:conversa_n8n) { create(:conversation, account: account, inbox: caixa_n8n, status: :open) }

    before do
      create(:agent_bot_inbox, inbox: caixa_n8n, agent_bot: n8n)
      contrato!(ordem: true, robo: nil)
    end

    it 'webhook vai para o n8n e o ReplyJob não responde nem pergunta ao CRM' do
      mensagem = cliente_escreve('oi', conversa_n8n)

      expect { AgentBotListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: mensagem)) }
        .to have_enqueued_job(AgentBots::WebhookJob).with(n8n.outgoing_url, anything, anything, anything)

      gatilho(mensagem, conversa_n8n)
      expect(settles_na_fila).to be_empty
      expect(contrato).not_to have_received(:ordem_do_turno?)
    end

    it 'claim: a resposta do n8n o faz dono' do
      robo_posta(n8n, conversa_n8n)

      expect(conversa_n8n.reload.ai_assignee).to eq(n8n)
    end

    it 'devolução: desatribuir a pessoa volta ao n8n' do
      conversa_n8n.update!(assignee: pessoa)

      expect(desatribuir(conversa_n8n).ai_assignee).to eq(n8n)
    end
  end

  # Conta fora da Fase 2 com linhas em crm_inbox_ai_agents (o contexto cria uma) e o adaptador dizendo o contrário de
  # tudo: espere, há robô de funil. Tudo segue como no main.
  describe 'cenário 15: conta fora da Fase 2' do
    before do
      Autonomia::Agents::Fase2.desligar!(account)
      contrato!(ordem: true, robo: espelho_area)
    end

    it 'a porta responde mesmo com o ai_assignee trocado durante a IA, sem refazer turno' do
      expect(Crm::InboxAiAgent.where(account: account)).to exist
      ia_responde!(durante: ->(agente) { conversation.update!(ai_assignee: espelho_area) if agente == agente_da_porta })
      mensagem = cliente_escreve('oi')
      gatilho(mensagem)

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas.sole.sender_id).to eq(porta.id)
      expect(linhas.grep(/\[autonomia\]\[turno\]/)).to be_empty
      expect(contrato).not_to have_received(:ordem_do_turno?)
    end

    it 'o claim troca para quem postou, e a devolução vai para a porta' do
      conversation.update!(ai_assignee: espelho_area)
      robo_posta(porta)
      expect(conversation.reload.ai_assignee).to eq(porta)

      conversation.update!(assignee: pessoa)
      expect(desatribuir.ai_assignee).to eq(porta)
      expect(contrato).not_to have_received(:robo_do_funil)
    end
  end

  # Testar e Copiloto chamam o Answerer direto: não passam pelo ReplyJob nem postam na conversa.
  it 'cenário 16: Testar e Copiloto não enfileiram turno nem fazem claim' do
    ia_responde!
    antes = conversation.reload.ai_assignee

    Autonomia::Agents::Playground.new(agent: agente_da_porta, message: 'Oi', history: [], images: []).run
    Autonomia::Agents::Copilot.new(agent: agente_da_porta, message: 'Oi').suggest

    expect(jobs_de(UmTurnoHelper::REPLY_JOB)).to be_empty
    expect(conversation.reload.ai_assignee).to eq(antes)
    expect(respostas).to be_empty
    expect(contrato).not_to have_received(:ordem_do_turno?)
  end

  it 'cenário 17: nenhuma linha do turno leva texto do cliente ou do modelo' do
    segredo_do_cliente = 'meu CPF é 123.456.789-00 SEGREDO-DO-CLIENTE'
    texto_do_modelo = 'TEXTO-DO-MODELO com dado sensível'
    contrato!(ordem: true, robo: espelho_area)
    ia_responde!(texto: texto_do_modelo, durante: ->(agente) { trocar_dono!(espelho_area) if agente == agente_da_porta })

    linhas = linhas_do_log do
      gatilho(cliente_escreve(segredo_do_cliente))
      rodar_turno! # espera, atrasa, troca de dono, reenfileira, barra
      robo_posta(porta) # claim barrado
      conversation.update!(assignee: pessoa)
      desatribuir # devolução
    end

    do_turno = linhas.grep(/\[autonomia\]\[(turno|operate)\]/)
    eventos = do_turno.filter_map { |linha| linha[/\[autonomia\]\[turno\] (\w+)/, 1] }.uniq
    expect(eventos).to include('assunto_atrasou', 'turno_reenfileirado', 'reenfileiramento_barrado', 'claim_barrado', 'devolucao')
    expect(do_turno.grep(/motivo=dono_mudou/)).not_to be_empty
    do_turno.each do |linha|
      expect(linha).not_to include('SEGREDO-DO-CLIENTE', '123.456.789', 'TEXTO-DO-MODELO')
    end
  end
end
