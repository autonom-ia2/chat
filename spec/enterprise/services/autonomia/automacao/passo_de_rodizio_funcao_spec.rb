require 'rails_helper'

# #2502 "com permissão": o passo "atribuir em rodízio" com quem ligou numa função personalizada. A troca entra pelo pedido
# do "Atribuir" como quem ligou, então vale o que a função deixa fazer na conversa (Enterprise::ConversationPolicy#show?).
# Quem pode operar a conversa sem responsável passa a conversa; quem deixa de poder pausa a automação, sem girar a fila.
RSpec.describe Autonomia::Automacao::PassoDeRodizio, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pessoa) { create(:user, account: account, role: :agent, name: 'Paula') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia') }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [pessoa, bia]) }
  let(:contato) { account.contacts.create!(name: 'Maria', phone_number: '+5511987652502') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let(:funcao) do
    CustomRole.create!(account: account, name: 'Distribuição', permissions: %w[automation_manage conversation_unassigned_manage])
  end
  let(:rodizio) { { 'id' => 'p2', 'tipo' => 'rodizio' } }

  before do
    ligar_motor(account)
    inbox.update!(enable_auto_assignment: false)
    AccountUser.find_by(account: account, user: pessoa).update!(custom_role: funcao)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ bia.id.to_s => 'online' })
  end

  after { Current.reset }

  def comecar_e_rodar(definicao)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa.reload, chave_gatilho: 'conversa.criada').call
    end
  end

  def ligada(passos) = automacao_ligada(account, pessoa, passos, gatilho: { 'tipo' => 'conversa.criada' })

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  it 'a função que opera a conversa sem responsável passa a conversa pelo rodízio', :aggregate_failures do
    execucao = comecar_e_rodar(ligada([rodizio]))

    expect(registros(execucao)).to eq([['p2', 'ok', nil]])
    expect(conversa.reload.assignee).to eq(bia)
  end

  it 'a função perde a chave da conversa durante a espera: pausa, sem girar a fila nem atribuir', :aggregate_failures do
    definicao = ligada([esperar_passo('p1'), rodizio])
    execucao = comecar_e_rodar(definicao)
    funcao.update!(permissions: %w[automation_manage])
    expect(AutoAssignment::AgentAssignmentService).not_to receive(:new)

    travel(1.day + 1.minute) { varrer }

    expect([execucao.reload.estado, registros(execucao).last.last]).to eq(%w[parada quem_ligou_sem_acesso])
    expect(definicao.reload.ativa).to be(false)
    expect(conversa.reload.assignee).to be_nil
  end
end
