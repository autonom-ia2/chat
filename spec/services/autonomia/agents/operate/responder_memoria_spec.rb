require 'rails_helper'

# A MEMÓRIA CONTA INTERAÇÕES DO CLIENTE (chat#625, 23/09/2026). A janela era de 32 mensagens, e cada pedido gera umas
# três do agente (texto, PDF, aviso): eram ~10 interações, e o CPF dado no começo da conversa sumia. Agora são as
# últimas `HISTORY_MAX_INTERACOES` mensagens do cliente e tudo o que veio depois delas.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end
  let(:config) { Autonomia::Agents::Config }
  let(:inicio) { 2.days.ago }

  # Cada interação: o cliente escreve, o agente responde com três mensagens (texto, PDF, aviso).
  def conversar(interacoes)
    interacoes.times do |n|
      mensagem(:incoming, "cliente #{n}", n * 4)
      3.times { |i| mensagem(:outgoing, "agente #{n}.#{i}", (n * 4) + i + 1) }
    end
  end

  def mensagem(tipo, texto, minuto)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo,
                     content: texto, created_at: inicio + minuto.minutes)
  end

  def historico
    described_class.new(conversation: conversation, agent_inbox: agent_inbox).send(:history)
  end

  it 'leva as últimas interações do cliente com tudo o que o agente respondeu no meio' do
    conversar(config::HISTORY_MAX_INTERACOES + 5)

    textos = historico.pluck(:content)

    expect(textos.first).to eq('cliente 5')
    expect(textos.count { |texto| texto.start_with?('cliente') }).to eq(config::HISTORY_MAX_INTERACOES)
    expect(textos).to include('agente 5.2')
    expect(textos.last).to eq("agente #{config::HISTORY_MAX_INTERACOES + 4}.2")
  end

  it 'o dado dado pelo cliente 20 interações atrás continua na memória' do
    mensagem(:incoming, 'o CPF dela é tal', 0)
    3.times { |i| mensagem(:outgoing, "agente #{i}", i + 1) }
    19.times do |n|
      mensagem(:incoming, "cliente #{n}", (n + 1) * 4)
      3.times { |i| mensagem(:outgoing, "agente #{n}.#{i}", ((n + 1) * 4) + i + 1) }
    end

    expect(historico.pluck(:content)).to include('o CPF dela é tal')
  end

  # O TETO DE CARACTERES NÃO CORTA ANTES DAS 25 (revisão da #625). Medido na conversa 7057 em 23/09/2026: 25
  # interações são 84 mensagens e 8,7 mil caracteres (média 103, maior 605). Aqui, no ritmo real (três mensagens do
  # agente por interação) e com quatro vezes a média: 400 por mensagem do agente, 150 do cliente, ~34 mil no total.
  # A primeira interação continua no que vai ao modelo.
  it 'com mensagens do tamanho real, as 25 interações cabem no teto de caracteres do histórico' do
    config::HISTORY_MAX_INTERACOES.times do |n|
      mensagem(:incoming, "cliente #{n} #{'x' * 150}", n * 4)
      3.times { |i| mensagem(:outgoing, "agente #{n}.#{i} #{'y' * 400}", (n * 4) + i + 1) }
    end

    enviado = Autonomia::Agents::PromptParts::Historico.capar(historico)

    expect(enviado.first[:content]).to start_with('cliente 0 ')
  end

  it 'conversa curta vai inteira' do
    conversar(3)

    expect(historico.size).to eq(12)
  end

  it 'nota privada e atividade não entram' do
    conversar(2)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content: 'nota interna', private: true, created_at: inicio + 30.minutes)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity,
                     content: 'atribuída', created_at: inicio + 31.minutes)

    expect(historico.pluck(:content)).not_to include('nota interna', 'atribuída')
  end

  it 'o teto de mensagens segura a lista quando o agente fala demais, e ficam as mais recentes' do
    stub_const('Autonomia::Agents::Config::HISTORY_MAX_MESSAGES', 10)
    conversar(5)

    textos = historico.pluck(:content)

    expect(textos.size).to eq(10)
    expect(textos.last).to eq('agente 4.2')
  end
end
