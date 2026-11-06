require 'rails_helper'

# O passo "email" (#2414 G2) com quem ligou numa função personalizada: estar na caixa de e-mail não basta. Ele precisa
# poder começar conversa, como no "Nova conversa" do painel (ConversationPolicy#create?, #1800). A função que só lê
# pausa a automação.
RSpec.describe Autonomia::Automacao::PassoDeEmail, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { create(:channel_email, account: account).inbox }
  let(:contato) { create(:contact, account: account, email: 'cliente@exemplo.com', name: 'Carla') }
  let(:whatsapp) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, contact: contato, inbox: whatsapp) }
  let(:passo) { { 'id' => 'p1', 'tipo' => 'email', 'caixa_id' => caixa.id, 'assunto' => ['Seu pedido'], 'texto' => ['Saiu.'] } }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  after { Current.reset }

  def ligada_por_funcao(permissions)
    pessoa = create(:user, account: account, role: :agent)
    funcao = CustomRole.create!(account: account, name: "Função #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: pessoa).update!(custom_role: funcao)
    caixa.add_members([pessoa.id])
    definicao = automacao_ligada(account, admin, [passo])
    definicao.update_column(:ligada_por_id, pessoa.id) # rubocop:disable Rails/SkipsModelValidations
    Autonomia::Automacao::Execucao.new(automacao: definicao.reload, account: account)
  end

  def executar(execucao) = described_class.new(execucao: execucao, passo: passo, alvo: conversa).executar

  it 'função que só lê, membro da caixa: pausa (sem_acesso) e não abre conversa', :aggregate_failures do
    resultado = executar(ligada_por_funcao(%w[conversation_view automation_manage]))

    expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'quem_ligou_sem_acesso'])
    expect(Conversation.where(inbox: caixa)).to be_empty
  end

  it 'função que opera conversa, membro da caixa: manda', :aggregate_failures do
    resultado = executar(ligada_por_funcao(%w[conversation_view conversation_participating_manage automation_manage]))

    expect(resultado.tipo).to eq(:ok)
    expect(Conversation.where(inbox: caixa).count).to eq(1)
  end
end
