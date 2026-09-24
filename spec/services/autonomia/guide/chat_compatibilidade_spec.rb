require 'rails_helper'

# Contrato de compatibilidade do `Chat::Result` (#636, revisão #637): as listas `navigations`/
# `artigos` são a fonte nova, e os campos singulares `navigation`/`artigo` continuam existindo —
# sempre o PRIMEIRO item de cada lista — para um pedido aberto antes do deploy e lido depois (ou o
# contrário, no blue/green) não cair num campo que sumiu.
RSpec.describe Autonomia::Guide::Chat do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }

  it 'traz as listas inteiras, com o singular igual ao primeiro item de cada uma', :aggregate_failures do
    agente = instance_double(Autonomia::Agents::Agent)
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(agente)
    allow(Autonomia::Agents::Retriever).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))

    tela_a = { route_name: 'labels_list', params: {}, highlight: nil, rotulo: 'Etiquetas' }
    tela_b = { route_name: 'settings_inbox_new', params: {}, highlight: nil, rotulo: nil }
    artigo_a = { ref: '02-04', titulo: 'Conectar o WhatsApp' }

    # O stub do Answerer faz o papel das ferramentas: é dentro delas que `mostrar_tela` e
    # `ler_da_central` de verdade chamariam `contexto.mostrar`/`contexto.artigo_lido`.
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      kwargs[:operador].mostrar(tela_a)
      kwargs[:operador].mostrar(tela_b)
      kwargs[:operador].artigo_lido(ref: artigo_a[:ref], titulo: artigo_a[:titulo])
      instance_double(Autonomia::Agents::Answerer,
                      answer: Autonomia::Agents::AnswerResult.new(reply: 'Aqui estão os passos.',
                                                                  confidence: 1.0,
                                                                  handoff: { should: false, reason: nil }))
    end

    resultado = described_class.new(account: conta, user: admin, message: 'conectar whatsapp e ver etiquetas').perform

    expect(resultado.navigations).to eq([tela_a, tela_b])
    expect(resultado.navigation).to eq(tela_a)
    expect(resultado.artigos).to eq([artigo_a])
    expect(resultado.artigo).to eq(artigo_a)
  end

  it 'quando nada foi mostrado nem lido, as listas ficam vazias e o singular fica nulo', :aggregate_failures do
    agente = instance_double(Autonomia::Agents::Agent)
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(agente)
    allow(Autonomia::Agents::Retriever).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
    allow(Autonomia::Agents::Answerer).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Answerer,
                                  answer: Autonomia::Agents::AnswerResult.new(reply: 'Oi.', confidence: 1.0,
                                                                              handoff: { should: false, reason: nil })))

    resultado = described_class.new(account: conta, user: admin, message: 'oi').perform

    expect(resultado.navigations).to eq([])
    expect(resultado.navigation).to be_nil
    expect(resultado.artigos).to eq([])
    expect(resultado.artigo).to be_nil
  end
end
