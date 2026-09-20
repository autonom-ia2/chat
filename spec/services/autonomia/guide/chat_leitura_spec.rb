require 'rails_helper'

# Liga o Guia à leitura do estado da conta (#533): a pergunta "o que eu tenho?"
# passa a ser respondida com os dados da conta, e não com o manual.
RSpec.describe Autonomia::Guide::Chat do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:agente_ia) { instance_double(Autonomia::Agents::Agent) }

  # O que o Answerer recebeu — é ali que o bloco de leitura precisa aparecer.
  def perguntar(mensagem, usuario: admin, fluxo: '- leitura: `funis`')
    query = nil
    resultado = instance_double(
      Autonomia::Agents::AnswerResult,
      reply: 'resposta', answered_from_knowledge: true, confidence: 0.9, handoff: {},
      used_knowledge: []
    )

    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(agente_ia)
    allow(Autonomia::Agents::Retriever).to receive(:new).and_return(
      instance_double(Autonomia::Agents::Retriever,
                      retrieve: [instance_double(Autonomia::Agents::KnowledgeEntry, content: fluxo)])
    )
    allow(Autonomia::Agents::Answerer).to receive(:new) do |args|
      query = args[:query]
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end

    described_class.new(account: conta, user: usuario, message: mensagem).perform
    query.to_s
  end

  it 'responde "quais funis eu tenho" com o que a conta tem', :aggregate_failures do
    inbox = create_crm_inbox(account: conta, name: 'Comercial', members: [admin])
    pipeline, stage = create_crm_pipeline(account: conta, user: admin)
    conta.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: true)

    query = perguntar('Quais funis eu tenho?')

    expect(query).to include('[O QUE A CONTA TEM')
    expect(query).to include('Comercial')
    expect(query).to include('cria card sozinho')
  end

  it 'não lê nada quando a pergunta é de como fazer' do
    create_crm_pipeline(account: conta, user: admin)

    expect(perguntar('Como eu crio um funil?')).not_to include('[O QUE A CONTA TEM')
  end

  it 'não lê nada quando o fluxo recuperado não pede leitura' do
    create_crm_pipeline(account: conta, user: admin)

    expect(perguntar('Quais funis eu tenho?', fluxo: '- gotchas: nada aqui')).not_to include('[O QUE A CONTA TEM')
  end

  it 'não entrega configuração da conta ao agente comum', :aggregate_failures do
    agente, = create_crm_agent(account: conta)
    create_crm_pipeline(account: conta, user: admin, name: 'Funil Secreto')

    query = perguntar('Quais funis eu tenho?', usuario: agente)

    expect(query).not_to include('Funil Secreto')
    expect(query).to include('quem vê é o administrador')
  end
end
