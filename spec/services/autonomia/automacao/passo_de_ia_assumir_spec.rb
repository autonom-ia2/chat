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

  it 'a passagem fica gravada no CRM com o motivo da automação, pelo contrato de verdade' do
    allow(contrato).to receive(:registrar_passagem!).and_call_original
    allow(contrato).to receive(:com_motivo_da_passagem).and_call_original

    rodar

    expect(Crm::Passagem.where(conversation_id: conversation.id).order(:id).last).to have_attributes(motivo: 'automacao')
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

  # Decisão 18 (exemplo 17): a opção "mesmo com uma pessoa na conversa", desligada por padrão, deixa a agente assumir
  # a conversa de uma pessoa, pedida por quem ligou (como o "Passar para…" da tela). O histórico guarda de quem.
  context 'with a opção mesmo com uma pessoa na conversa' do
    let(:passo) { { 'id' => 'p1', 'tipo' => 'ia_assumir', 'agente_id' => area.id, 'mesmo_com_pessoa' => true } }

    it 'tira a conversa da pessoa, pedida por quem ligou, e registra de quem foi tirada', :aggregate_failures do
      conversation.update!(assignee: pessoa)

      execucao = rodar

      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
      expect(registro(execucao)).to have_attributes(resultado: 'ok',
                                                    dados: { 'agente_id' => area.id, 'tirada_de' => pessoa.id, 'trocou' => true })
      expect(contrato).to have_received(:registrar_passagem!).with(hash_including(para: area, pedida_por: admin))
    end

    it 'sem pessoa no nome, passa como sempre, pelo CRM e sem tirada_de', :aggregate_failures do
      execucao = rodar

      expect(registro(execucao).dados).to eq('agente_id' => area.id, 'trocou' => true)
      expect(contrato).to have_received(:registrar_passagem!).with(hash_including(para: area, pedida_por: nil))
    end

    it 'no ensaio, com pessoa no nome, diz que passaria' do
      conversation.update!(assignee: pessoa)

      expect(described_class.ensaiar(passo, conversation)).to eq(['ia_assumir', { agente: 'Área Suporte' }])
    end
  end

  it 'a opção desligada (false) é o padrão: a pessoa fica', :aggregate_failures do
    conversation.update!(assignee: pessoa)

    execucao = rodar(automacao_ligada(account, admin, [passo.merge('mesmo_com_pessoa' => false)]))

    expect(registro(execucao)).to have_attributes(resultado: 'pulado', motivo: 'pessoa_atribuida')
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

  # O desvio que o G15 fecha: o passo "ação" de atribuir mandava `assignee_type: AgentBot` e passava a conversa ao robô
  # sem a Atribuição. A lista agora proíbe o campo ao salvar e o motor confere de novo ao rodar, para a versão salva antes.
  describe 'o atribuir da lista de ações' do
    def atribuir(id, corpo)
      { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST conversations/:conversation_id/assignments', 'descricao' => 'Atribuir',
        'caminho' => { 'conversation_id' => { '$valor' => 'conversa.id' } }, 'corpo' => corpo }
    end

    it 'versão salva antes da regra com assignee_type: o motor recusa ao rodar e a conversa não muda de dono' do
      robo = create(:agent_bot, account: account)
      automacao = automacao_ligada(account, admin, [atribuir('p1', { 'assignee_id' => pessoa.id })])
      antiga = automacao.versao_ativa.receita.deep_dup
      antiga['passos'][0]['corpo'] = { 'assignee_type' => 'AgentBot', 'assignee_id' => robo.id }
      # Gravada antes da regra: a validação de hoje não a deixaria salvar, e a versão é só leitura.
      Autonomia::Automacao::Versao.where(id: automacao.versao_ativa_id).update_all(receita: antiga) # rubocop:disable Rails/SkipsModelValidations

      execucao = rodar(automacao)

      expect(registro(execucao)).to have_attributes(resultado: 'falhou', motivo: 'acao_recusada')
      expect(conversation.reload.ai_assignee).to eq(porta)
    end

    it 'a receita com assignee_type não salva' do
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' },
                  'passos' => [atribuir('p1', { 'assignee_type' => 'AgentBot', 'assignee_id' => 1 })] }

      problemas = Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas

      expect(problemas.join).to include('assignee_type')
    end
  end

  describe '.opcoes' do
    it 'traz só id e nome das agentes que recebem conversa numa caixa da conta, porta e área' do
      expect(described_class.opcoes(account)).to contain_exactly({ id: agente_da_porta.id, name: 'Porta' },
                                                                 { id: area.id, name: 'Área Suporte' })
    end

    it 'são as mesmas que cada caixa receberia, numa consulta só, com uma caixa ou com várias', :aggregate_failures do
      outra = create(:inbox, account: account)
      Autonomia::Agents::Areas.vincular!(agent: criar_agente('Comercial'), inbox: outra)
      pela_caixa = account.inboxes.flat_map { |caixa| Autonomia::Agents::PassarParaIa.destinos_na_caixa(caixa) }.uniq.map(&:id)
      consultas = lambda do
        contadas = 0
        contar = ->(*, dados) { contadas += 1 unless dados[:name] == 'SCHEMA' || dados[:cached] }
        ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') { described_class.opcoes(account) }
        contadas
      end
      com_duas = consultas.call
      3.times { |n| Autonomia::Agents::Areas.vincular!(agent: criar_agente("Extra #{n}"), inbox: create(:inbox, account: account)) }

      extras = Autonomia::Agents::Agent.where(name: ['Extra 0', 'Extra 1', 'Extra 2']).ids
      expect(described_class.opcoes(account).pluck(:id)).to match_array(pela_caixa + extras)
      expect(consultas.call).to eq(com_duas)
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
    it 'diz para quem passaria, ou o motivo, sem chamar a passagem' do
      expect(Crm::Entrega::ParaIa).not_to receive(:passar!)

      expect(described_class.ensaiar(passo, conversation)).to eq(['ia_assumir', { agente: 'Área Suporte' }])
      conversation.update!(assignee: pessoa)
      expect(described_class.ensaiar(passo, conversation)).to eq(['pessoa_atribuida', { agente: 'Área Suporte' }])
    end

    # O ensaio não chama o serviço dos Agentes, então repete as perguntas dele: aqui as duas respostas lado a lado.
    {
      'passa' => -> {},
      'pessoa no nome' => -> { conversation.update!(assignee: pessoa) },
      'conversa resolvida' => -> { conversation.update!(status: :resolved) },
      'agente sem vínculo na caixa' => -> { area_sumiu! },
      'agente que não atende cliente' => -> { area.update_column(:enabled, false) }, # rubocop:disable Rails/SkipsModelValidations
      'resolvida e com a agente sem atender' => lambda {
        conversation.update!(status: :resolved)
        area.update_column(:enabled, false) # rubocop:disable Rails/SkipsModelValidations
      },
      'agentes desligadas na conta' => -> { allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(false) }
    }.each do |cenario, preparar|
      it "#{cenario}: o ensaio diz o que a passagem de verdade diz" do
        instance_exec(&preparar)

        no_ensaio = described_class.ensaiar(passo, conversation.reload).first
        de_verdade = Crm::Entrega::ParaIa.passar!(conversation: conversation, agent: area.reload, por: :crm, motivo: 'automacao')

        expect(no_ensaio).to eq(de_verdade == Crm::Entrega::ParaIa::PASSOU ? 'ia_assumir' : de_verdade)
      end
    end
  end
end
