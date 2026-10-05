require 'rails_helper'

# #861 — depois de responder, o job grava no turno da conversa a resposta e o
# diagnóstico do pedido.
RSpec.describe Autonomia::Guide::ChatJob do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:pedido) { Autonomia::Guide::Pedido.abrir(account: conta, user: admin) }
  let(:conversa) { Autonomia::Guide::Conversa.create!(account: conta, user: admin, titulo: 'etiquetas') }
  let!(:turno) { Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: pedido, pergunta: 'cria a etiqueta vip', tela: 'home') }

  def rodar
    described_class.perform_now(pedido, { 'account_id' => conta.id, 'user_id' => admin.id, 'mensagem' => 'cria a etiqueta vip',
                                          'historico' => [], 'tela' => 'home', 'locale' => 'pt_BR' })
  end

  # O Guia de mentira faz o que o de verdade faz num turno: chama uma ferramenta,
  # executa uma ação anotada para desfazer e paga uma ida ao modelo.
  def guia_que_age
    allow(Autonomia::Guide::Chat).to receive(:new) do |**kwargs|
      instance_double(Autonomia::Guide::Chat).tap do |chat|
        allow(chat).to receive(:perform) { agir(kwargs[:registro]) }
      end
    end
  end

  def agir(registro)
    Autonomia::Guide::Contexto.new(account: conta, user: admin, registro: registro).registrar_chamada(
      { 'name' => 'executar_acao', 'arguments' => { acao: 'POST labels', corpo_json: '{"title":"vip"}' }.to_json },
      'Pronto.', 12
    )
    execucao = Autonomia::Guide::Execucao.abrir(account: conta, user: admin)
    Autonomia::Guide::Diario.gravando(execucao, 0) { conta.labels.create!(title: 'vip') }
    execucao.registrar_passo(acao: 'POST labels', frase: 'Criei a etiqueta vip.', feito: true)
    Crm::Ai::UsageRecorder.record(account: conta, feature: 'guia', model: 'gpt-5.6-sol', usage: { input_tokens: 10 })
    registro.decidir(confianca: 0.9, grounded: true, execution_id: execucao.id)
    Autonomia::Guide::Chat::Result.new(text: 'Criei a etiqueta vip.', available: true, execucao: execucao.resumo)
  end

  it 'grava o turno pronto, com o diagnóstico e o que o Guia fez', :aggregate_failures do
    guia_que_age

    rodar

    turno.reload
    expect(turno.status).to eq('done')
    expect(turno.resposta).to eq('Criei a etiqueta vip.')
    # O resumo da execução leva `acao` e `registro` desde o #859 (o selo "Criada pelo Guia").
    expect(turno.passos).to eq([{ 'acao' => 'POST labels', 'frase' => 'Criei a etiqueta vip.', 'ok' => true, 'registro' => nil }])
    expect(turno.execucao).to be_present
    expect(turno.diagnostico).to include('rodadas' => 1, 'confianca' => 0.9, 'grounded' => true)
    expect(turno.diagnostico['chamadas'].first).to include('ferramenta' => 'executar_acao', 'omitidos' => ['corpo_json'])
  end

  # Dentro de `Diario.gravando` toda escrita vira mudança do Guia, e o desfazer
  # apagaria o próprio registro. O turno é gravado depois, fora do caderno.
  it 'não anota o registro como mudança do Guia' do
    guia_que_age

    rodar

    expect(Autonomia::Guide::Mudanca.pluck(:tabela)).to eq(['labels'])
  end

  # O que vai para o modelo (instrução, catálogo, trechos da base) nunca entra
  # no diagnóstico: só metadado.
  it 'não guarda a instrução, o catálogo nem o texto da base no diagnóstico', :aggregate_failures do
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(instance_double(Autonomia::Agents::Agent, id: 0))
    allow(Autonomia::Agents::Retriever).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
    recebido = {}
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      recebido = kwargs
      instance_double(Autonomia::Agents::Answerer, answer: Autonomia::Agents::AnswerResult.new(
        reply: '', raw_reply: 'o texto que o portão segurou', confidence: 0.2, handoff: { should: false, reason: nil },
        used_knowledge: [{ id: 5, content: 'conteúdo do fluxo da base', source: 'Criar etiqueta' }]
      ))
    end

    rodar

    diagnostico = turno.reload.diagnostico
    expect(recebido[:query]).to include('CONTEXTO INTERNO')
    expect(recebido[:feature]).to eq('guia')
    expect(turno.status).to eq('retido')
    expect(diagnostico).to include('retido' => true, 'resposta_retida' => 'o texto que o portão segurou',
                                   'fluxos' => [{ 'id' => 5, 'titulo' => 'Criar etiqueta' }])
    expect(diagnostico.to_json).not_to include('CONTEXTO INTERNO', 'RECURSOS QUE VOCÊ PODE LER', 'conteúdo do fluxo da base')
  end

  it 'marca o turno como falho, com a classe do erro e sem a mensagem', :aggregate_failures do
    allow(Autonomia::Guide::Chat).to receive(:new).and_raise(ArgumentError, 'o telefone 11999998888 caiu')

    rodar

    turno.reload
    expect(turno.status).to eq('failed')
    expect(turno.diagnostico['erro']).to eq('ArgumentError')
    expect(turno.diagnostico.to_json).not_to include('11999998888')
  end

  it 'marca o Guia fora do ar como falha no turno, com o motivo', :aggregate_failures do
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(nil)
    allow(Autonomia::Guide::Seed).to receive(:ensure_async_for).and_return(false)

    rodar

    expect(turno.reload.status).to eq('failed')
    expect(turno.diagnostico['erro']).to eq('indisponivel')
  end
end
