require 'rails_helper'

# #2000 — a conta única da IA. Critério de pronto: para o mesmo agente e o mesmo período, CRM › Números › Equipe (a linha
# da IA, Crm::Numeros::IaNoTime) e a página do agente (Autonomia::AgentesSemanaFinder) mostram o mesmo número de
# atendidas, passadas e resolvidas sozinha.
RSpec.describe Autonomia::ContaDaIa do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:venda) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:atende) do
    pipeline = account.crm_pipelines.create!(name: 'Suporte', created_by: admin, status: :active, counts_as_sale: false)
    [pipeline, account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Aberto', position: 0)]
  end
  let(:bia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:espelho) { create(:agent_bot, account: account, name: 'Bia') }
  let(:semana) { described_class.semana(account) }

  # A Equipe recebe os funis por um objeto com `tem?` e `ids`; aqui, os dois funis, como o dono da conta vê.
  let(:funis) do
    ids = { venda: [venda.first.id], atende: [atende.first.id] }
    Struct.new(:ids_por_tipo) do
      def tem?(tipo) = ids_por_tipo[tipo].any?
      def ids(tipo) = ids_por_tipo[tipo]
    end.new(ids)
  end

  around { |example| travel_to(Time.utc(2026, 10, 21, 15, 0)) { example.run } }

  before do
    Autonomia::Agents::AgentInbox.create!(agent: bia, inbox: inbox, account: account, agent_bot: espelho)
    allow(Crm::Ai::ExchangeRate).to receive(:current).and_return(rate: 5.0, fetched_at: nil)
  end

  def conversa_no(funil)
    pipeline, stage = funil
    chat = create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account))
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: admin, primary_conversation: chat, title: "Card #{chat.id}")
    chat
  end

  def resposta(chat, quando: 1.day.ago, robo: espelho)
    create(:message, account: account, inbox: chat.inbox, conversation: chat, message_type: :outgoing, sender: robo,
                     created_at: quando)
  end

  def passagem(chat, quando: 1.day.ago)
    Crm::Passagem.create!(account: account, conversation: chat, de_type: 'Autonomia::Agents::Agent', de_id: bia.id, de_nome: 'Bia',
                          para_type: 'User', para_id: admin.id, para_nome: admin.name, motivo: 'robo_pediu', em: quando)
  end

  def resolvida(chat, quando: 1.day.ago)
    create(:reporting_event, account: account, conversation_id: chat.id, name: 'conversation_resolved', event_end_time: quando)
  end

  def equipe
    Crm::Numeros::IaNoTime.new(account: account, range: semana, cards: funis, ganhos: { ids: [], moeda: 'BRL' }, custo: false).perform
  end

  def pagina
    Autonomia::AgentesSemanaFinder.new(account: account, agent_ids: [bia.id]).call.first
  end

  it 'Equipe e página do agente leem o mesmo número para o mesmo agente e a mesma semana' do
    respondida_duas_vezes = conversa_no(venda)
    resposta(respondida_duas_vezes)
    resposta(respondida_duas_vezes, quando: 2.days.ago)
    passada = conversa_no(atende)
    resposta(passada)
    passagem(passada)
    passagem(passada, quando: 2.days.ago)
    por_horario = conversa_no(venda)
    passagem(por_horario)
    sozinha = conversa_no(atende)
    resposta(sozinha)
    resolvida(sozinha)
    antiga = conversa_no(atende)
    resposta(antiga, quando: 10.days.ago)
    passagem(antiga, quando: 10.days.ago)

    linha_da_ia = equipe
    cartoes = pagina

    expect(linha_da_ia).to include(nome: 'Bia', agenteId: bia.id, atendeu: 3, passou: 2)
    expect(linha_da_ia[:atende]).to eq(resolveuSozinha: 1)
    expect(cartoes).to eq(agent_id: bia.id, answered: 3, handed: 2, resolved: 1)
    expect([cartoes[:answered], cartoes[:handed], cartoes[:resolved]])
      .to eq([linha_da_ia[:atendeu], linha_da_ia[:passou], linha_da_ia[:atende][:resolveuSozinha]])
  end

  it 'a lista de cada número tem as mesmas conversas que o número conta' do
    respondida = conversa_no(venda)
    resposta(respondida)
    resposta(respondida)
    passada = conversa_no(venda)
    passagem(passada)
    sozinha = conversa_no(atende)
    resposta(sozinha)
    resolvida(sozinha)

    conta = described_class.new(account: account, range: semana)
    numeros = conta.por_agente([bia.id])[bia.id]

    expect(conta.conversas_do_agente(bia.id, :atendeu).pluck(:id)).to contain_exactly(respondida.id, sozinha.id)
    expect(conta.conversas_do_agente(bia.id, :passou).pluck(:id)).to contain_exactly(passada.id)
    expect(conta.conversas_do_agente(bia.id, :resolveuSozinha).pluck(:id)).to contain_exactly(sozinha.id)
    expect(numeros).to eq(atendeu: 2, passou: 1, resolveuSozinha: 1)
  end

  it 'só a nota do encaminhamento e a passagem: atendeu 0, passou 1 (nota interna não é resposta)' do
    chat = conversa_no(atende)
    create(:message, account: account, inbox: chat.inbox, conversation: chat, message_type: :outgoing, sender: espelho,
                     private: true, created_at: 1.day.ago)
    passagem(chat)
    resolvida(chat)

    conta = described_class.new(account: account, range: semana)

    expect(conta.da_ia).to eq(atendeu: 0, passou: 1, resolveuSozinha: 0)
    expect(conta.por_agente([bia.id])[bia.id]).to eq(atendeu: 0, passou: 1, resolveuSozinha: 0)
    expect(equipe).to include(atendeu: 0, passou: 1)
  end

  it 'toda a IA soma qualquer robô; o agente conta só os espelhos dele' do
    n8n = create(:agent_bot, account: account, name: 'n8n')
    so_do_n8n = conversa_no(venda)
    resposta(so_do_n8n, robo: n8n)
    resposta(conversa_no(venda))

    conta = described_class.new(account: account, range: semana)

    expect(conta.da_ia).to include(atendeu: 2)
    expect(conta.por_agente([bia.id])[bia.id]).to include(atendeu: 1)
  end

  it 'conta só o universo dado e nunca outra conta' do
    fora = create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account))
    resposta(fora)
    dentro = conversa_no(venda)
    resposta(dentro)
    outra_conta = create(:account)
    alheia = create(:conversation, account: outra_conta)
    create(:message, account: outra_conta, inbox: alheia.inbox, conversation: alheia, message_type: :outgoing, sender: espelho,
                     created_at: 1.day.ago)

    universo = Conversation.where(id: dentro.id)

    expect(described_class.new(account: account, range: semana, conversas: universo).por_agente([bia.id])[bia.id])
      .to include(atendeu: 1)
    expect(described_class.new(account: account, range: semana).por_agente([bia.id])[bia.id]).to include(atendeu: 2)
  end

  it 'a semana são os últimos 7 dias, contando hoje, desde a meia-noite no fuso da conta' do
    expect(semana.begin).to eq(Time.utc(2026, 10, 15, 3, 0))
    expect(semana.end).to eq(Time.current)
  end

  it 'à noite no Brasil, "hoje" ainda é o dia do Brasil, não o do servidor' do
    travel_back
    travel_to(Time.utc(2026, 10, 22, 1, 0))

    expect(described_class.semana(account).begin).to eq(Time.utc(2026, 10, 15, 3, 0))
  end

  it 'a resolvida e a passagem gravadas muito antes do período não entram, mesmo com a data do evento dentro' do
    chat = conversa_no(atende)
    resposta(chat)
    passagem(chat).update!(created_at: 30.days.ago)
    resolvida(chat).update!(created_at: 30.days.ago)

    expect(described_class.new(account: account, range: semana).da_ia).to include(passou: 0, resolveuSozinha: 0)
  end
end
