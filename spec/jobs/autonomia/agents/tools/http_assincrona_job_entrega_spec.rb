require 'rails_helper'

# #1430, revisão final do PR assíncrono (lado do job): o resultado nunca fica mudo quando nenhum turno vai entregar
# (B1, B3), a desistência marcada só depois do fechamento que confere o prazo (G), o defeito antes do envio como falha
# certa (G) e a linha limpa pela exclusão da conversa (E, LGPD).
RSpec.describe Autonomia::Agents::Tools::HttpAssincronaJob, type: :job do
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
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Consultar pedido', slug: 'consultar_pedido', timeout_seconds: 60,
      endpoint_url: 'https://erp.exemplo.test/pedidos',
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end
  let(:runs) { Autonomia::Agents::ToolRun }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    agent_inbox
    ligar_consulta_em_segundo_plano
  end

  # A linha aberta por um turno que NÃO desistiu (morreu, ou ainda espera): sem marca de entrega.
  def consulta_sem_marca
    relogio_do_turno
    entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 77)
    Autonomia::Agents::Tools::ConsultaNoTurno.new(tool: tool, agente: agent, turno: entrega, args: { 'numero' => '42' }).disparar
    clear_enqueued_jobs
    runs.sole
  end

  def passada_de_volta?(run)
    enqueued_jobs.any? { |job| job[:job] == described_class && job[:args] == [run.id] && job[:at].present? }
  end

  describe 'B1: o turno morreu antes de desistir' do
    it 'o resultado chega na janela: a linha fica viva para o turno, e a passada volta quando a janela vence' do
      run = consulta_sem_marca
      sistema_responde('{"status":"enviado"}')

      described_class.new.perform(run.id)

      expect(run.reload).to have_attributes(status: 'running', entrega: nil)
      expect(run.resultado_da_consulta).to eq('{"status":"enviado"}')
      expect(eventos_disparados(run)).to be_empty
      expect(passada_de_volta?(run)).to be(true)
    end

    it 'vencida a janela sem marca: a passada que volta marca a desistencia e o evento fala, uma vez' do
      run = consulta_sem_marca
      sistema_responde('{"status":"enviado"}')
      described_class.new.perform(run.id)

      travel(described_class::FOLGA_DA_JANELA + 9.seconds) { described_class.new.perform(run.id) }

      expect(run.reload).to have_attributes(status: 'done', entrega: runs::DESISTIU_DO_TURNO)
      expect(eventos_disparados(run)).to eq(['consulta_concluida'])
    end

    it 'o resultado que chega depois da janela, sem marca: o evento fala na hora' do
      run = consulta_sem_marca
      sistema_responde('{"status":"enviado"}')

      travel(1.minute) { described_class.new.perform(run.id) }

      expect(run.reload).to have_attributes(status: 'done', entrega: runs::DESISTIU_DO_TURNO)
      expect(eventos_disparados(run)).to eq(['consulta_concluida'])
    end

    it 'o turno que marcou a entrega antes da volta ganha: a volta so fecha, sem evento' do
      run = consulta_sem_marca
      sistema_responde('{"status":"enviado"}')
      described_class.new.perform(run.id)
      run.reload.marcar_entregue!(por: 'mensagem:77')

      travel(1.minute) { described_class.new.perform(run.id) }

      expect(run.reload).to have_attributes(status: 'done', entrega: runs::ENTREGUE_NO_TURNO)
      expect(eventos_disparados(run)).to be_empty
    end

    it 'o varredor fecha a linha com resultado e sem marca (a volta se perdeu): desistencia e evento' do
      run = consulta_sem_marca
      sistema_responde('{"status":"enviado"}')
      described_class.new.perform(run.id)
      runs.where(id: run.id).update_all(expires_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations

      travel(1.minute) { Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform }

      expect(run.reload).to have_attributes(status: 'done', entrega: runs::DESISTIU_DO_TURNO)
      expect(eventos_disparados(run)).to eq(['consulta_concluida'])
    end
  end

  describe 'B3 e G: a incerta e o abandono marcam a desistencia depois do fechamento' do
    it 'a reentrada do mesmo job depois da chamada, fora da janela: incerta, com o evento' do
      run = consulta_sem_marca
      run.merge_handle!({ runs::CHAMADA_FEITA => true, runs::PASSADA => 'jid-1' })
      passada = described_class.new
      allow(passada).to receive(:job_id).and_return('jid-1')

      travel(1.minute) { passada.perform(run.id) }

      expect(run.reload).to have_attributes(status: 'failed', failure_code: runs::INCERTA, entrega: runs::DESISTIU_DO_TURNO)
      expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    end

    it 'o varredor que perde a corrida do prazo (o job renovou) nao grava desistencia' do
      run = consulta_sem_marca
      run.merge_handle!({ runs::CHAMADA_FEITA => true })

      expect(described_class.incerta(run, vencida_antes_de: 5.minutes.ago)).to be(false)
      expect(described_class.abandonar(run, vencida_antes_de: 5.minutes.ago)).to be(false)
      expect(run.reload.entrega).to be_nil
    end
  end

  describe 'G: o defeito nosso antes do envio' do
    it 'e falha certa: consulta_falhou normal (nao incerta), no rastreador, e o erro sobe' do
      run = consulta_sem_marca
      run.merge_handle!({ runs::ENTREGA => runs::DESISTIU_DO_TURNO })
      allow(SafeFetch).to receive(:fetch)
      allow(Autonomia::Agents::Tools::EnderecoDaFerramenta).to receive(:new).and_raise(NoMethodError, 'defeito')
      rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)

      expect { described_class.new.perform(run.id) }.to raise_error(NoMethodError)

      expect(SafeFetch).not_to have_received(:fetch)
      expect(rastreador).to have_received(:capture_exception)
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'tool_execution_error')
      expect(run.handle).not_to include(runs::POSSIVELMENTE_DUPLICADA)
      expect(eventos_disparados(run)).to eq(['consulta_falhou'])
    end
  end

  describe 'E: LGPD, a conversa excluida no meio da chamada' do
    it 'a limpeza antes do gravar: o corpo nao volta para a linha' do
      run = consulta_sem_marca
      sistema_responde('{"cpf":"123.456.789-00"}', antes: lambda {
        Autonomia::Agents::RegistroDaConversaExcluida.new(account_id: account.id, conversation_id: conversation.id).perform
      })

      described_class.new.perform(run.id)

      run.reload
      expect(run.status).to eq('blocked')
      expect(run.handle.to_json).not_to include('123.456.789-00')
      expect(run.resultado_gravado?).to be(false)
    end

    it 'a linha superada que a limpeza alcancou tambem nao recebe o corpo' do
      run = consulta_sem_marca
      runs.where(id: run.id).update_all(status: 'superseded') # rubocop:disable Rails/SkipsModelValidations
      Autonomia::Agents::RegistroDaConversaExcluida.new(account_id: account.id, conversation_id: conversation.id).perform

      expect(run.reload.gravar_resultado!('{"cpf":"1"}', sucesso: true, codigo: nil, api_ms: 1)).to be(false)
      expect(run.reload.resultado_gravado?).to be(false)
    end
  end
end
