require 'rails_helper'

# G19 (#2636) com quem ligou numa função personalizada: a nota no contato passa pela mesma porta da tela de notas
# (NotesController, ContactPolicy#update?). O salvar não confere a pessoa; quem barra é o rodar. A função sem
# contact_manage pausa a automação e nenhuma nota é gravada.
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:passo) do
    { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST contacts/:contact_id/notes', 'descricao' => 'Anotar no contato',
      'caminho' => { 'contact_id' => { '$valor' => 'contato.id' } }, 'corpo' => { 'content' => 'Próxima revisão em maio.' } }
  end

  before { ligar_motor(account) }

  after { Current.reset }

  def rodar_ligada_por_funcao(permissions)
    pessoa = create(:user, account: account, role: :agent)
    funcao = CustomRole.create!(account: account, name: "Função #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: pessoa).update!(custom_role: funcao)
    conversa.inbox.add_members([pessoa.id])
    automacao = automacao_ligada(account, admin, [passo])
    automacao.update_column(:ligada_por_id, pessoa.id) # rubocop:disable Rails/SkipsModelValidations
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao.reload, conversa) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  it 'função sem contact_manage: pausa (sem acesso) e nenhuma nota é gravada', :aggregate_failures do
    execucao = rodar_ligada_por_funcao(%w[conversation_manage contact_view automation_manage])

    expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[p1 falhou quem_ligou_sem_acesso]]])
    expect(contato.notes.count).to eq(0)
  end

  it 'função com contact_manage: grava a nota no nome de quem ligou', :aggregate_failures do
    execucao = rodar_ligada_por_funcao(%w[conversation_manage contact_manage automation_manage])

    expect([execucao.reload.estado, registros(execucao)]).to eq(['concluida', [['p1', 'ok', nil]]])
    expect(contato.notes.pluck(:content, :user_id)).to eq([['Próxima revisão em maio.', execucao.automacao.ligada_por_id]])
  end
end
