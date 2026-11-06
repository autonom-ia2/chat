require 'rails_helper'

# G15 (#2414): o passo "Passar para a agente de IA" passa a conversa pela Atribuição (Crm::Entrega::ParaIa), como o CRM
# pede (`por: :crm`). Pessoa no nome vence; toda recusa vira pulo com o código; erro inesperado sobe ao executor.
RSpec.describe Autonomia::Automacao::PassoDeIaAssumir, :automacao_motor, :um_turno do
  include ActiveJob::TestHelper
  include_context 'with crm responsible agent'

  let(:pessoa) { create(:user, account: account, role: :agent) }
  let(:passo) { { 'id' => 'p1', 'tipo' => 'ia_assumir', 'agente_id' => area.id } }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    ligar_motor(account)
    contrato!
    allow(contrato).to receive(:registrar_passagem!)
    allow(contrato).to receive(:com_motivo_da_passagem).and_yield
  end

  after { Current.reset }

  def rodar(automacao = automacao_ligada(account, admin, [passo]))
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao, conversation) }
  end

  def registro(execucao) = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'p1')

  it 'passa a conversa à agente pela Atribuição, como o CRM, e registra a passagem com o motivo da automação' do
    execucao = rodar

    expect(conversation.reload.ai_assignee).to eq(espelho_area)
    expect(registro(execucao)).to have_attributes(resultado: 'ok', dados: { 'agente_id' => area.id, 'trocou' => true })
    expect(contrato).to have_received(:registrar_passagem!).with(hash_including(para: area, motivo: 'automacao', pedida_por: nil))
    expect(execucao.reload.estado).to eq('concluida')
  end

  it 'com a agente já dona da conversa, segue sem trocar' do
    conversation.update!(ai_assignee: espelho_area)

    expect(registro(rodar)).to have_attributes(resultado: 'ok', dados: { 'agente_id' => area.id, 'trocou' => false })
  end

  it 'com uma pessoa no nome, a pessoa fica e o passo pula com pessoa_atribuida' do
    conversation.update!(assignee: pessoa)

    expect(registro(rodar)).to have_attributes(resultado: 'pulado', motivo: 'pessoa_atribuida')
    expect(conversation.reload.assignee).to eq(pessoa)
  end

  it 'agente sem vínculo na caixa da conversa: pula com o código, nunca passa para outra' do
    automacao = automacao_ligada(account, admin, [passo])
    area_sumiu!

    expect(registro(rodar(automacao))).to have_attributes(resultado: 'pulado', motivo: 'sem_vinculo_na_caixa')
    expect(conversation.reload.ai_assignee).to eq(porta)
  end

  it 'com as agentes desligadas na conta depois de salvar, não age' do
    automacao = automacao_ligada(account, admin, [passo])
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(false)

    expect(registro(rodar(automacao))).to have_attributes(resultado: 'pulado', motivo: 'fase2_desligada')
    expect(conversation.reload.ai_assignee).to eq(porta)
  end

  it 'conversa resolvida não recebe ninguém' do
    automacao = automacao_ligada(account, admin, [passo])
    conversation.update!(status: :resolved)

    expect(registro(rodar(automacao))).to have_attributes(resultado: 'pulado', motivo: 'conversa_resolvida')
  end

  it 'agente apagada entre salvar e rodar: pula com agente_sumiu' do
    automacao = automacao_ligada(account, admin, [passo])
    area.update!(deleted_at: Time.current)

    expect(registro(rodar(automacao))).to have_attributes(resultado: 'pulado', motivo: 'agente_sumiu')
    expect(conversation.reload.ai_assignee).to eq(porta)
  end

  it 'erro inesperado na passagem sobe: a execução fica com a falha à vista, nunca concluída' do
    automacao = automacao_ligada(account, admin, [passo])
    allow(Crm::Entrega::ParaIa).to receive(:passar!).and_raise(ActiveRecord::StatementInvalid, 'caiu')

    comecar(automacao, conversation)
    job = enqueued_jobs.find { |enfileirado| enfileirado['job_class'] == Autonomia::Automacao::AvancarJob.name }

    expect { ActiveJob::Base.execute(job) }.to raise_error(ActiveRecord::StatementInvalid)
    execucao = Autonomia::Automacao::Execucao.find_by!(automacao: automacao)
    expect(registro(execucao)).to have_attributes(resultado: 'falhou', motivo: 'erro_inesperado')
    expect(execucao.reload.estado).not_to eq('concluida')
  end

  it 'card sem conversa principal pula com sem_conversa' do
    automacao = automacao_ligada(account, admin, [passo], gatilho: { 'tipo' => 'conversa.resolvida' })
    card = account.crm_cards.create!(pipeline: suporte, stage: suporte.stages.first, contact: contact, inbox: inbox, title: 'Sem conversa')

    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao, card) }

    expect(registro(execucao)).to have_attributes(resultado: 'pulado', motivo: 'sem_conversa')
  end

  it 'a troca sai assinada pela automação (Ato) e não redispara a mesma automação pela conversa que ela reabriu' do
    conversation.update!(status: :pending)
    automacao = automacao_ligada(account, admin, [passo], gatilho: { 'tipo' => 'conversa.aberta' })
    assinada = nil
    allow(Crm::Entrega::ParaIa).to receive(:passar!).and_wrap_original do |original, **args|
      assinada = Autonomia::Automacao::Ato.automacao_id
      original.call(**args)
    end

    perform_enqueued_jobs(only: [EventDispatcherJob, Autonomia::Automacao::AvancarJob]) { comecar(automacao, conversation) }

    expect(assinada).to eq(automacao.id)
    expect(conversation.reload).to have_attributes(status: 'open', ai_assignee: espelho_area)
    expect(Autonomia::Automacao::Execucao.where(automacao: automacao).count).to eq(1)
  end

  describe '.opcoes' do
    it 'traz só id e nome das agentes que recebem conversa numa caixa da conta, porta e área' do
      expect(described_class.opcoes(account)).to contain_exactly({ id: agente_da_porta.id, name: 'Porta' },
                                                                  { id: area.id, name: 'Área Suporte' })
    end

    it 'sem as agentes ligadas na conta, nenhuma' do
      allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(false)

      expect(described_class.opcoes(account)).to eq([])
    end
  end

  describe '.problemas_ao_salvar' do
    it 'recusa agente de outra conta' do
      de_fora = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Outra', agent_type: 'custom', status: :active,
                                                 enabled: true)

      expect(described_class.problemas_ao_salvar(account, passo.merge('agente_id' => de_fora.id)).first).to include('p1')
      expect(described_class.problemas_ao_salvar(account, passo)).to eq([])
    end
  end

  describe '.ensaiar' do
    it 'diz para quem passaria, ou o motivo, sem chamar o serviço dos Agentes' do
      allow(Autonomia::Agents::PassarParaIa).to receive(:call)

      expect(described_class.ensaiar(passo, conversation)).to eq(['ia_assumir', { agente: 'Área Suporte' }])
      conversation.update!(assignee: pessoa)
      expect(described_class.ensaiar(passo, conversation)).to eq(['pessoa_atribuida', { agente: 'Área Suporte' }])
      expect(Autonomia::Agents::PassarParaIa).not_to have_received(:call)
    end
  end
end
