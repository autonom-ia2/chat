require 'rails_helper'

# G15 (#2414, parecer de Funções): o passo "Passar para a agente de IA" age como quem ligou a automação, conferido de
# novo na hora de rodar. Quem ligou e, entre o começo e a rodada, passou a uma função que só lê a conversa ou que nem a
# vê não passa a conversa: a rodada para antes do passo e a automação pausa, como nos outros passos que agem na
# conversa. Fica em spec/enterprise: a
# metade de função personalizada é EE.
RSpec.describe Autonomia::Automacao::PassoDeIaAssumir, :aggregate_failures, :automacao_motor, :um_turno do
  include ActiveJob::TestHelper
  include_context 'with crm responsible agent'

  let(:passo) { { 'id' => 'p1', 'tipo' => 'ia_assumir', 'agente_id' => area.id } }
  let(:dono) do
    user = create(:user, account: account, role: :agent)
    AccountUser.find_by(account: account, user: user).update!(custom_role: funcao('conversation_manage'))
    create(:inbox_member, user: user, inbox: inbox)
    user
  end

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

  def funcao(*permissoes) = create(:custom_role, account: account, permissions: ['automation_manage', *permissoes])

  # Começa com quem ligou alcançando a conversa; a função muda antes da rodada.
  def rodar_depois(&mudar)
    automacao = automacao_ligada(account, dono, [passo])
    execucao = comecar(automacao, conversation)
    mudar&.call(AccountUser.find_by(account: account, user: dono))
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob)
    [automacao.reload, execucao.reload]
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  it 'função que gerencia conversas na caixa passa a conversa' do
    _automacao, execucao = rodar_depois

    expect(registros(execucao)).to eq([%w[p1 ok] + [nil]])
    expect(conversation.reload.ai_assignee).to eq(espelho_area)
  end

  it 'passou a uma função que só lê a conversa: não passa, e a automação pausa' do
    automacao, execucao = rodar_depois { |na_conta| na_conta.update!(custom_role: funcao('conversation_view')) }

    expect(registros(execucao)).to eq([%w[inicio pulado quem_ligou_sem_acesso]])
    expect([automacao.ativa, conversation.reload.ai_assignee]).to eq([false, porta])
  end

  it 'saiu da caixa da conversa, mesmo gerenciando conversas: não passa, e a automação pausa' do
    automacao, execucao = rodar_depois { InboxMember.where(user: dono, inbox: inbox).destroy_all }

    expect(registros(execucao)).to eq([%w[inicio pulado quem_ligou_sem_acesso]])
    expect([automacao.ativa, conversation.reload.ai_assignee]).to eq([false, porta])
  end
end
