require 'rails_helper'

# "Cobrir a pessoa enquanto ela não responde" (decisão 18, corrigida; exemplo 17): a conversa só volta para a pessoa que
# a agente de IA tirou, quando ela escreve ao cliente, na conversa coberta por uma execução aberta da mesma conta; e
# volta também quando a execução fecha, a automação é desligada ou o Motor sai, para a IA nunca ficar presa.
RSpec.describe Autonomia::Automacao::Cobertura do
  include ActiveJob::TestHelper

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

  # O registro do começo da cobertura, como o PassoDeIaAssumir grava na troca (opção cobrir_pessoa).
  def cobrir(exec = execucao, agente_id: 1)
    described_class.comecar!(exec, 'sofia', conversa, renata.id, agente_id)
  end

  def mensagem(tipo: :outgoing, sender: renata, privada: false, content_attributes: {})
    create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: tipo, sender: sender,
                     private: privada, content: 'Oi, Maria!', content_attributes: content_attributes)
  end

  def registros(motivo) = Autonomia::Automacao::Registro.where(motivo: motivo)
  def voltas = registros(described_class::VOLTOU)
  def encerradas = registros(described_class::ENCERRADA)

  before do
    account.enable_features!(Autonomia::Automacao::FLAG_FUNDACAO, Autonomia::Automacao::Motor::FLAG)
    create(:inbox_member, user: renata, inbox: conversa.inbox)
    create(:inbox_member, user: paula, inbox: conversa.inbox)
    conversa.update!(ai_assignee: robo)
  end

  describe 'a pessoa escreve' do
    it 'a pessoa tirada escreve: a conversa volta para ela e o histórico registra', :aggregate_failures do
      cobrir
      described_class.pessoa_escreveu(mensagem)

      expect(conversa.reload).to have_attributes(assignee_id: renata.id, assignee_agent_bot_id: nil)
      expect(voltas.pluck(:execucao_id, :passo, :resultado, :dados))
        .to eq([[execucao.id, 'sofia', 'ok', { 'pessoa_id' => renata.id, 'conversa_id' => conversa.id }]])
      expect(described_class.vigente(conversa)).to be_nil
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

    it 'execução já fechada não devolve pela mensagem', :aggregate_failures do
      cobrir
      execucao.update!(estado: 'concluida')

      described_class.pessoa_escreveu(mensagem)

      expect(conversa.reload.assignee_id).to be_nil
      expect(voltas).to be_empty
    end

    it 'sem cobertura ativa, nada muda', :aggregate_failures do
      escrita = mensagem
      allow(Conversations::AssignmentService).to receive(:new).and_call_original

      described_class.pessoa_escreveu(escrita)

      expect(Conversations::AssignmentService).not_to have_received(:new)
      expect(conversa.reload.assignee_id).to be_nil
      expect(voltas).to be_empty
    end

    it 'mensagem que não é de pessoa sai cedo, sem procurar cobertura', :aggregate_failures do
      do_cliente = mensagem(tipo: :incoming, sender: conversa.contact)
      allow(Autonomia::Automacao::Registro).to receive(:where).and_call_original
      allow(Autonomia::Automacao::Execucao).to receive(:abertas).and_call_original

      described_class.pessoa_escreveu(do_cliente)

      expect(Autonomia::Automacao::Registro).not_to have_received(:where)
      expect(Autonomia::Automacao::Execucao).not_to have_received(:abertas)
    end

    it 'conversa sem a IA, ou com uma pessoa no nome, sai cedo, sem procurar cobertura', :aggregate_failures do
      cobrir
      escrita = mensagem
      allow(Autonomia::Automacao::Execucao).to receive(:abertas).and_call_original

      conversa.update!(ai_assignee: nil)
      described_class.pessoa_escreveu(escrita.reload)
      conversa.update!(ai_assignee: robo, assignee: paula)
      described_class.pessoa_escreveu(escrita.reload)

      expect(Autonomia::Automacao::Execucao).not_to have_received(:abertas)
    end

    it 'com a automação desligada na conta, a mensagem sai cedo e não devolve', :aggregate_failures do
      cobrir
      escrita = mensagem
      account.disable_features!(Autonomia::Automacao::Motor::FLAG)
      allow(Autonomia::Automacao::Execucao).to receive(:abertas).and_call_original

      described_class.pessoa_escreveu(escrita.reload)

      expect(Autonomia::Automacao::Execucao).not_to have_received(:abertas)
      expect(voltas).to be_empty
    end
  end

  describe 'o fim da cobertura' do
    it 'a execução fecha: a conversa volta para a pessoa tirada, com cobertura_encerrada', :aggregate_failures do
      cobrir
      execucao.update!(estado: 'concluida')

      described_class.encerrar([execucao.id])

      expect(conversa.reload).to have_attributes(assignee_id: renata.id, assignee_agent_bot_id: nil)
      expect(encerradas.pluck(:execucao_id, :resultado, :dados))
        .to eq([[execucao.id, 'ok', { 'pessoa_id' => renata.id, 'conversa_id' => conversa.id }]])
    end

    it 'a automação é desligada: as coberturas das execuções abertas devolvem a conversa', :aggregate_failures do
      cobrir

      execucao.automacao.desligar!

      expect(conversa.reload.assignee_id).to eq(renata.id)
      expect(encerradas.count).to eq(1)
    end

    it 'o Motor sai da conta: a varredura devolve a conversa, uma vez só', :aggregate_failures do
      cobrir
      account.disable_features!(Autonomia::Automacao::Motor::FLAG)

      2.times { Autonomia::Automacao::VarreduraJob.perform_now }

      expect(conversa.reload.assignee_id).to eq(renata.id)
      expect(encerradas.count).to eq(1)
    end

    it 'com o Motor ligado, a varredura não mexe na cobertura', :aggregate_failures do
      cobrir

      Autonomia::Automacao::VarreduraJob.perform_now

      expect(conversa.reload.assignee_id).to be_nil
      expect(encerradas).to be_empty
    end

    it 'cobertura que já terminou, ou conversa que outra pessoa pegou, não muda no fim', :aggregate_failures do
      cobrir
      described_class.pessoa_escreveu(mensagem)
      conversa.update!(assignee: paula)

      described_class.encerrar([execucao.id])

      expect(conversa.reload.assignee_id).to eq(paula.id)
      expect(encerradas).to be_empty
    end
  end

  # Parecer da Funções (#2859): a conversa só volta para quem ainda a vê (Acesso.alcanca?, a pergunta do passo "conversa
  # ao responsável"). Sem acesso, fica com a agente de IA, e a cobertura termina com pessoa_sem_acesso.
  describe 'a pessoa tirada não vê mais a conversa' do
    def sem_acesso = registros(described_class::SEM_ACESSO)

    def registro_sem_acesso(para) = [execucao.id, 'ok', { 'para' => para, 'pessoa_id' => renata.id, 'conversa_id' => conversa.id }]

    def expect_com_a_ia(para)
      expect(conversa.reload).to have_attributes(assignee_id: nil, ai_assignee: robo)
      expect(sem_acesso.pluck(:execucao_id, :resultado, :dados)).to eq([registro_sem_acesso(para)])
      expect(voltas + encerradas).to be_empty
      expect(described_class.vigente(conversa)).to be_nil
    end

    it 'saiu da caixa e a execução fechou: a conversa fica com a IA, uma vez só', :aggregate_failures do
      cobrir
      InboxMember.find_by(user: renata, inbox: conversa.inbox).destroy!
      execucao.update!(estado: 'concluida')

      2.times { described_class.encerrar([execucao.id]) }

      expect_com_a_ia(described_class::ENCERRADA)
    end

    it 'saiu da caixa e a automação foi desligada: a conversa fica com a IA', :aggregate_failures do
      cobrir
      InboxMember.find_by(user: renata, inbox: conversa.inbox).destroy!

      execucao.automacao.desligar!

      expect_com_a_ia(described_class::ENCERRADA)
    end

    it 'saiu da conta e o Motor saiu: a varredura deixa a conversa com a IA, uma vez só', :aggregate_failures do
      cobrir
      AccountUser.find_by(account: account, user: renata).destroy!
      account.disable_features!(Autonomia::Automacao::Motor::FLAG)

      2.times { Autonomia::Automacao::VarreduraJob.perform_now }

      expect_com_a_ia(described_class::ENCERRADA)
    end

    it 'a mensagem dela, já sem a caixa, também não devolve a conversa', :aggregate_failures do
      cobrir
      escrita = mensagem
      InboxMember.find_by(user: renata, inbox: conversa.inbox).destroy!

      described_class.pessoa_escreveu(escrita)

      expect_com_a_ia(described_class::VOLTOU)
    end

    it 'administradora vê toda conversa: a conversa volta para ela mesmo sem a caixa', :aggregate_failures do
      cobrir
      InboxMember.find_by(user: renata, inbox: conversa.inbox).destroy!
      AccountUser.find_by(account: account, user: renata).update!(role: :administrator)

      described_class.encerrar([execucao.id])

      expect(conversa.reload.assignee_id).to eq(renata.id)
      expect(sem_acesso).to be_empty
    end
  end

  describe 'a volta, sob a trava' do
    it 'trava a conversa e devolve uma vez só, mesmo chamada duas vezes com a cobertura já lida', :aggregate_failures do
      cobertura = cobrir
      allow(conversa).to receive(:with_lock).and_call_original
      allow(Conversations::AssignmentService).to receive(:new).and_call_original

      2.times { described_class.devolver(cobertura, conversa, described_class::VOLTOU) }

      # Uma trava por volta, mais a do próprio AssignmentService#assign_agent na única volta que devolve.
      expect(conversa).to have_received(:with_lock).exactly(3).times
      expect(Conversations::AssignmentService).to have_received(:new).once
      expect(voltas.count).to eq(1)
    end

    it 'a volta que falha grava falhou na execução, com o motivo, e a cobertura continua', :aggregate_failures do
      cobrir
      escrita = mensagem
      allow(Conversations::AssignmentService).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'dado do cliente')

      described_class.pessoa_escreveu(escrita)

      expect(registros(described_class::NAO_DEVOLVEU).pluck(:execucao_id, :resultado, :dados))
        .to eq([[execucao.id, 'falhou', { 'para' => described_class::VOLTOU, 'erro' => 'ActiveRecord::StatementInvalid',
                                          'conversa_id' => conversa.id }]])
      expect(voltas).to be_empty
      expect(described_class.vigente(conversa)).to be_present
    end

    it 'o fim que falha também grava falhou, e não levanta para quem fecha a execução', :aggregate_failures do
      cobrir
      allow(Conversations::AssignmentService).to receive(:new).and_raise(ActiveRecord::StatementInvalid)

      expect { described_class.encerrar([execucao.id]) }.not_to raise_error
      expect(registros(described_class::NAO_DEVOLVEU).pick(:dados)).to include('para' => described_class::ENCERRADA)
    end
  end

  # Decisão 18, revisão: a IA só segura o galho "a cada mensagem" enquanto pode atender a conversa.
  describe 'cobrindo? (o galho do "esperar até")' do
    around do |exemplo|
      with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { exemplo.run }
    end

    let(:sofia) do
      account.update!(internal_attributes: account.internal_attributes.to_h.merge(Autonomia::Agents::Config::INTERNAL_ATTR_KEY => true))
      Autonomia::Agents::Fase2.ligar!(account)
      Autonomia::Agents::Agent.create!(account: account, name: 'Sofia', agent_type: 'custom', status: :active, enabled: true)
    end
    let(:vinculo) { Autonomia::Agents::Areas.vincular!(agent: sofia, inbox: conversa.inbox) }

    before do
      conversa.update!(ai_assignee: vinculo.agent_bot)
      cobrir(agente_id: sofia.id)
    end

    it 'a agente pode atender: cobre' do
      expect(described_class.cobrindo?(conversa.reload, execucao)).to be(true)
    end

    it 'Fase 2 desligada: não cobre, e o galho abre' do
      Autonomia::Agents::Fase2.desligar!(account)

      expect(described_class.cobrindo?(conversa.reload, execucao)).to be(false)
    end

    it 'a agente parou de atender: não cobre' do
      sofia.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.cobrindo?(conversa.reload, execucao)).to be(false)
    end

    it 'a agente perdeu o vínculo com a caixa: não cobre' do
      vinculo.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.cobrindo?(conversa.reload, execucao)).to be(false)
    end

    it 'cobertura de outra execução não conta para esta' do
      outra = execucao_aberta(account, create(:conversation, account: account))

      expect(described_class.cobrindo?(conversa.reload, outra)).to be(false)
    end
  end
end
