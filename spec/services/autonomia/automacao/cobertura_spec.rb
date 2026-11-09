require 'rails_helper'

# "Cobrir a pessoa enquanto ela não responde" (decisão 18, corrigida; exemplo 17): a conversa só volta para a pessoa que
# a agente de IA tirou, quando ela escreve ao cliente, na conversa coberta por uma execução aberta da mesma conta.
RSpec.describe Autonomia::Automacao::Cobertura do
  let(:account) { create(:account) }
  let(:renata) { create(:user, account: account, role: :agent, name: 'Renata') }
  let(:paula) { create(:user, account: account, role: :agent, name: 'Paula') }
  let(:robo) { create(:agent_bot, account: account) }
  let(:conversa) { create(:conversation, account: account, assignee: nil) }
  let(:execucao) { execucao_aberta(account, conversa) }

  def execucao_aberta(conta, alvo)
    versao = create(:autonomia_automacao_versao, automacao: create(:autonomia_automacao, account: conta))
    create(:autonomia_automacao_execucao, versao: versao, alvo: alvo, estado: 'esperando')
  end

  # O registro do passo da agente que tirou a conversa da Renata (PassoDeIaAssumir, opção cobrir_pessoa).
  def cobrir(exec = execucao)
    create(:autonomia_automacao_registro, execucao: exec, passo: 'sofia', resultado: 'ok',
                                          dados: { 'agente_id' => 1, 'tirada_de' => renata.id, 'cobrindo_conversa' => conversa.id })
  end

  def mensagem(tipo: :outgoing, sender: renata, privada: false, content_attributes: {})
    create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: tipo, sender: sender,
                     private: privada, content: 'Oi, Maria!', content_attributes: content_attributes)
  end

  def voltas = Autonomia::Automacao::Registro.where(motivo: described_class::VOLTOU)

  before do
    account.enable_features!(Autonomia::Automacao::FLAG_FUNDACAO, Autonomia::Automacao::Motor::FLAG)
    create(:inbox_member, user: renata, inbox: conversa.inbox)
    create(:inbox_member, user: paula, inbox: conversa.inbox)
    conversa.update!(ai_assignee: robo)
  end

  it 'a pessoa tirada escreve: a conversa volta para ela e o histórico registra', :aggregate_failures do
    cobrir
    described_class.pessoa_escreveu(mensagem)

    expect(conversa.reload.assignee_id).to eq(renata.id)
    expect(voltas.pluck(:execucao_id, :passo, :resultado, :dados))
      .to eq([[execucao.id, 'sofia', 'ok', { 'pessoa_id' => renata.id, 'conversa_id' => conversa.id }]])
    expect(described_class.vigente(conversa)).to be_nil
  end

  it 'ela já ficou com a conversa ao enviar: só registra a volta, sem atribuir de novo', :aggregate_failures do
    cobrir
    conversa.update!(assignee: renata)
    allow(Conversations::AssignmentService).to receive(:new).and_call_original

    described_class.pessoa_escreveu(mensagem)

    expect(Conversations::AssignmentService).not_to have_received(:new)
    expect(voltas.count).to eq(1)
  end

  it 'depois da volta, a mensagem seguinte dela não registra outra volta' do
    cobrir
    2.times { described_class.pessoa_escreveu(mensagem) }

    expect(voltas.count).to eq(1)
  end

  it 'nota privada dela não devolve a conversa', :aggregate_failures do
    cobrir
    described_class.pessoa_escreveu(mensagem(privada: true))

    expect(conversa.reload.assignee_id).to be_nil
    expect(voltas).to be_empty
  end

  it 'mensagem do cliente, da IA, de bot sem remetente ou envio automático no nome dela não devolve', :aggregate_failures do
    cobrir
    [mensagem(tipo: :incoming, sender: conversa.contact),
     mensagem(sender: robo),
     mensagem(sender: nil),
     mensagem(content_attributes: { 'automacao_id' => execucao.automacao_id })].each do |outra|
      described_class.pessoa_escreveu(outra)
    end

    expect(conversa.reload).to have_attributes(assignee_id: nil, ai_assignee: robo)
    expect(voltas).to be_empty
  end

  it 'outra pessoa da equipe escrevendo não devolve a conversa', :aggregate_failures do
    cobrir
    described_class.pessoa_escreveu(mensagem(sender: paula))

    expect(conversa.reload.assignee_id).to be_nil
    expect(voltas).to be_empty
    expect(described_class.vigente(conversa)).to be_present
  end

  it 'a cobertura gravada em outra conta não devolve a conversa desta', :aggregate_failures do
    outra_conta = create(:account)
    cobrir(execucao_aberta(outra_conta, create(:conversation, account: outra_conta)))

    described_class.pessoa_escreveu(mensagem)

    expect(conversa.reload.assignee_id).to be_nil
    expect(voltas).to be_empty
  end

  it 'execução já fechada não devolve a conversa', :aggregate_failures do
    cobrir
    execucao.update!(estado: 'concluida')

    described_class.pessoa_escreveu(mensagem)

    expect(conversa.reload.assignee_id).to be_nil
    expect(voltas).to be_empty
  end

  it 'sem cobertura ativa, nada muda', :aggregate_failures do
    allow(Conversations::AssignmentService).to receive(:new).and_call_original

    described_class.pessoa_escreveu(mensagem)

    expect(Conversations::AssignmentService).not_to have_received(:new)
    expect(conversa.reload.assignee_id).to be_nil
    expect(voltas).to be_empty
  end

  it 'mensagem que não é de pessoa sai cedo, sem procurar cobertura', :aggregate_failures do
    allow(Autonomia::Automacao::Registro).to receive(:where).and_call_original
    allow(Autonomia::Automacao::Execucao).to receive(:abertas).and_call_original

    described_class.pessoa_escreveu(mensagem(tipo: :incoming, sender: conversa.contact))

    expect(Autonomia::Automacao::Registro).not_to have_received(:where)
    expect(Autonomia::Automacao::Execucao).not_to have_received(:abertas)
  end

  it 'conversa com outra pessoa no nome sai cedo, sem procurar cobertura' do
    cobrir
    conversa.update!(assignee: paula)
    allow(Autonomia::Automacao::Execucao).to receive(:abertas).and_call_original

    described_class.pessoa_escreveu(mensagem)

    expect(Autonomia::Automacao::Execucao).not_to have_received(:abertas)
  end

  it 'com a automação desligada na conta, não devolve' do
    cobrir
    account.disable_features!(Autonomia::Automacao::Motor::FLAG)

    described_class.pessoa_escreveu(mensagem)

    expect(voltas).to be_empty
  end
end
