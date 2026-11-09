require 'rails_helper'

# #1430, revisão do delta: a incerta só segura o mesmo pedido enquanto é recente; o defeito nosso ao fechar a linha não
# tira o resultado do turno; e o turno novo recupera a entrega de um turno superado que já tinha fechado a linha.
RSpec.describe Autonomia::Agents::Tools::ConsultaNoTurno do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:job) { Autonomia::Agents::Tools::HttpAssincronaJob }
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Consultar pedido', slug: 'consultar_pedido', timeout_seconds: 60,
      endpoint_url: 'https://erp.exemplo.test/pedidos',
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end
  let(:bound) { Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    agent_inbox
    tool
    ligar_consulta_em_segundo_plano
  end

  def turno(origem)
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: origem)
  end

  def chamada(id)
    { 'name' => 'consultar_pedido', 'arguments' => { numero: '42' }.to_json, 'call_id' => id }
  end

  def consulta(entrega)
    described_class.new(tool: tool, agente: agent, turno: entrega, args: { 'numero' => '42' })
  end

  def cliente_escreveu(message_id)
    allow(Autonomia::Agents::Fase2).to receive(:ligada?).and_return(true)
    stamp = { Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY => { 'pending_message_id' => message_id } }
    conversation.update!(additional_attributes: conversation.additional_attributes.to_h.merge(stamp))
  end

  describe '1: a incerta segura o mesmo pedido so enquanto e recente' do
    def incerta_fechada
      relogio_do_turno
      consulta(turno(10)).disparar
      run = runs.sole
      run.merge_handle!({ runs::CHAMADA_FEITA => true, runs::ENTREGA => runs::DESISTIU_DO_TURNO })
      job.incerta(run, vencida_antes_de: nil)
      clear_enqueued_jobs
      run.reload
    end

    it 'recente (dentro do tempo da ferramenta mais a carencia do varredor): segura, sem chamar de novo' do
      incerta_fechada

      saida = bound.execute(chamada('c2'), delivery: turno(12))

      expect(saida).to eq(described_class::INCERTA_JA_INFORMADA)
      expect(runs.count).to eq(1)
      expect(job).not_to have_been_enqueued
    end

    it 'antiga (a de segunda, na sexta): e pedido novo, e chama de novo' do
      run = incerta_fechada
      antiga = (tool.timeout_seconds.seconds + Autonomia::Agents::Tools::ReapStaleRunsJob::GRACE + 1.minute).ago
      runs.where(id: run.id).update_all(['handle = handle || ?::jsonb', { runs::ENCERRADA_EM => antiga.iso8601(3) }.to_json]) # rubocop:disable Rails/SkipsModelValidations

      saida = bound.execute(chamada('c2'), delivery: turno(12))

      expect(saida).to eq(described_class::EM_ANDAMENTO)
      expect(runs.count).to eq(2)
      expect(job).to have_been_enqueued.with(runs.order(:id).last.id)
    end
  end

  describe '2: o defeito nosso ao fechar a linha nao tira o resultado do turno' do
    it 'finish! levantando NoMethodError: o turno ainda devolve o resultado, e o defeito vai ao rastreador' do
      relogio_do_turno
      entrega = turno(10)
      consulta(entrega).disparar
      runs.sole.gravar_resultado!('{"status":"enviado"}', sucesso: true, codigo: nil, api_ms: 5)
      rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)
      allow_any_instance_of(runs).to receive(:finish!).and_raise(NoMethodError, 'defeito') # rubocop:disable RSpec/AnyInstance

      expect(consulta(entrega).resultado).to eq('{"status":"enviado"}')
      expect(rastreador).to have_received(:capture_exception)
      expect(runs.sole.entrega).to eq(runs::ENTREGUE_NO_TURNO)
    end
  end

  describe '3: o turno superado depois de fechar a linha' do
    def t1_entregou_e_fechou
      relogio_do_turno
      sistema_responde('{"status":"enviado"}')
      entrega = turno(10)
      consulta(entrega).disparar
      run = runs.sole
      run.merge_handle!({ runs::CHAMADA_FEITA => true })
      run.gravar_resultado!('{"status":"enviado"}', sucesso: true, codigo: nil, api_ms: 5)
      expect(consulta(entrega).resultado).to eq('{"status":"enviado"}')
      expect(run.reload.status).to eq('done')
      clear_enqueued_jobs
      run
    end

    it 'T1 superado sem postar: T2 entrega o resultado, sem chamar o sistema de fora' do
      run = t1_entregou_e_fechou
      cliente_escreveu(12)

      saida = bound.execute(chamada('c2'), delivery: turno(12))

      expect(saida).to eq('{"status":"enviado"}')
      expect(runs.count).to eq(1)
      expect(SafeFetch).not_to have_received(:fetch)
      expect(job).not_to have_been_enqueued
      expect(run.reload.entregue_por).to eq('mensagem:12')
    end

    it 'T1 ja postou a resposta: o pedido igual em mensagem nova e outro pedido, como antes' do
      t1_entregou_e_fechou
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing,
                       sender: agent_inbox.agent_bot, content: 'Seu pedido foi enviado.')
      cliente_escreveu(12)

      saida = bound.execute(chamada('c2'), delivery: turno(12))

      expect(saida).to eq(described_class::EM_ANDAMENTO)
      expect(runs.count).to eq(2)
    end
  end

  describe 'cavecrew 1: depois da marca de entrega deste turno, nenhuma falha vira em andamento' do
    def resultado_gravado
      relogio_do_turno
      entrega = turno(10)
      consulta(entrega).disparar
      runs.sole.gravar_resultado!('{"status":"enviado"}', sucesso: true, codigo: nil, api_ms: 5)
      entrega
    end

    it 'o defeito em concluir (a ocorrencia do turno) vai ao rastreador, e o turno devolve o resultado' do
      entrega = resultado_gravado
      rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)
      allow(entrega).to receive(:concluir_execucao).and_raise(NoMethodError, 'defeito')

      expect(consulta(entrega).resultado).to eq('{"status":"enviado"}')
      expect(rastreador).to have_received(:capture_exception)
    end

    it 'o banco falhando no fechamento depois da marca: o turno devolve o resultado, sem desistir' do
      entrega = resultado_gravado
      allow_any_instance_of(runs).to receive(:finish!).and_raise(ActiveRecord::ConnectionTimeoutError) # rubocop:disable RSpec/AnyInstance

      expect(consulta(entrega).resultado).to eq('{"status":"enviado"}')
      expect(runs.sole.entrega).to eq(runs::ENTREGUE_NO_TURNO)
    end
  end

  describe 'cavecrew 2: a incerta ja avisada pelo evento nao se repete' do
    def incerta_avisada(origem)
      relogio_do_turno
      consulta(turno(origem)).disparar
      run = runs.sole
      run.merge_handle!({ runs::CHAMADA_FEITA => true, runs::ENTREGA => runs::DESISTIU_DO_TURNO })
      job.incerta(run, vencida_antes_de: nil)
      clear_enqueued_jobs
      run.reload
    end

    it 'o mesmo turno refeito (a mesma chave) le a incerta ja informada, nao a recusa de novo' do
      incerta_avisada(10)

      expect(bound.execute(chamada('c9'), delivery: turno(10))).to eq(described_class::INCERTA_JA_INFORMADA)
    end

    it 'outro turno pendurado na mesma faixa tambem le a incerta ja informada' do
      incerta_avisada(10)

      expect(bound.execute(chamada('c9'), delivery: turno(12))).to eq(described_class::INCERTA_JA_INFORMADA)
      expect(described_class::INCERTA_JA_INFORMADA).not_to include('resultado foi')
    end

    it 'o turno que ainda espera na janela le a recusa da incerta, uma vez' do
      relogio_do_turno do
        run = runs.sole
        run.merge_handle!({ runs::CHAMADA_FEITA => true })
        job.incerta(run.reload, vencida_antes_de: nil)
      end

      saida = bound.execute(chamada('c1'), delivery: turno(10))

      expect(JSON.parse(saida)['error']).to eq(runs::INCERTA)
    end
  end
end
