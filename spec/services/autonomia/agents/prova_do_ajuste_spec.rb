require 'rails_helper'

# #1428 (tema 6, parte 3, entrega B) — as perguntas de prova do "Mudar conversando" no piloto. O Construtor escreve as
# perguntas no turno do ajuste; o cartão sai na hora com a prova pendente, e o job responde e julga depois. O resultado
# só é gravado enquanto o ajuste ainda é o último e vale (sem Desfazer nem ajuste novo no meio). O Answerer e o juiz são
# dublados aqui; que a prova não executa ferramenta nenhuma está em answerer_prova_spec.
RSpec.describe Autonomia::Agents::ProvaDoAjuste do
  include_context 'with ajuste por lista'

  let(:builder) { Autonomia::Agents::Builder.new(account: account, build_thread: thread) }
  let(:perguntas) { ['Quanto custa o seguro auto?', 'Vocês fazem seguro de vida?'] }
  let(:juiz) { instance_double(Autonomia::Agents::JuizDaProva) }
  let(:perguntados) { [] }

  def aplicar_ajuste(extra = {})
    respostas << saida({ 'tone' => 'cordial e curto', 'mudancas' => [mudanca('tone', fala, 'Respostas curtas.')],
                         'perguntas_de_prova' => perguntas }.merge(extra))
    run_turn
  end

  def versao_aplicada
    estado.dig('ultimo_ajuste', 'versao_id')
  end

  def agente_responde(*resultados)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      perguntados << kwargs
      instance_double(Autonomia::Agents::Answerer, answer: resultados.shift || resposta('Em até 2 frases.'))
    end
  end

  def resposta(texto, handoff: false, error: nil)
    Autonomia::Agents::AnswerResult.new(reply: texto, confidence: 0.9, handoff: { should: handoff, reason: nil }, error: error)
  end

  def provar!
    described_class.new(thread.reload, versao_aplicada).rodar!
  end

  before do
    allow(Autonomia::Agents::JuizDaProva).to receive(:new).and_return(juiz)
    allow(juiz).to receive(:julgar) { |itens:, **| Array.new(itens.size, 'ok') }
  end

  describe 'o fechamento do ajuste' do
    it 'grava a prova pendente com as perguntas e a versão do ajuste, e enfileira o job com a mesma versão' do
      aplicar_ajuste

      expect(estado['prova']).to include('status' => 'pendente', 'versao_id' => versao_aplicada,
                                         'perguntas' => perguntas.map { |pergunta| { 'pergunta' => pergunta } })
      expect(versao_aplicada).to be_present
      expect(Autonomia::Agents::ProvaDoAjusteJob).to have_been_enqueued.with(thread.id, versao_aplicada)
    end

    it 'sem perguntas do Construtor, sem prova e sem job' do
      aplicar_ajuste('perguntas_de_prova' => [])

      expect(estado['prova']).to be_nil
      expect(Autonomia::Agents::ProvaDoAjusteJob).not_to have_been_enqueued
    end

    it 'um ajuste novo troca a prova do anterior' do
      aplicar_ajuste
      primeira = versao_aplicada
      thread.append_message!('user', 'Agora mais formal')
      aplicar_ajuste('tone' => 'formal', 'mudancas' => [mudanca('tone', 'Agora mais formal', 'Tom formal.')],
                     'perguntas_de_prova' => ['Bom dia, tudo bem?'])

      expect(versao_aplicada).not_to eq(primeira)
      expect(estado['prova']).to include('versao_id' => versao_aplicada, 'perguntas' => [{ 'pergunta' => 'Bom dia, tudo bem?' }])
    end

    it 'a pergunta do dono (nada aplicado) não enfileira prova' do
      respostas << saida('so_pergunta' => true, 'next_question' => 'Ele atende os clientes.', 'perguntas_de_prova' => perguntas)

      run_turn

      expect(Autonomia::Agents::ProvaDoAjusteJob).not_to have_been_enqueued
      expect(estado['prova']).to be_nil
    end

    it 'a Lia (insurance_quote) fica fora: sem prova pendente' do
      agent.agent_type = 'insurance_quote'

      expect(described_class.pendente(agent, 'perguntas_de_prova' => perguntas, 'versao_id' => 1)).to be_nil
      expect(described_class.pendente(nil, 'perguntas_de_prova' => perguntas, 'versao_id' => 1)).to be_nil
    end

    it 'com correção, a prova é da versão da correção' do
      dados = { 'perguntas_de_prova' => perguntas, 'versao_id' => 1, 'correcao' => { 'versao_id' => 2 } }

      expect(described_class.pendente(agent, dados)['versao_id']).to eq(2)
    end
  end

  describe '#rodar!' do
    before { aplicar_ajuste }

    it 'responde cada pergunta em modo prova, com a feature própria, e grava pronta com o veredito do juiz' do
      agente_responde(resposta('Passo para a equipe.'), resposta(nil, handoff: true))
      allow(juiz).to receive(:julgar).and_return(%w[ok nao])

      provar!

      expect(perguntados.pluck(:query)).to eq(perguntas)
      expect(perguntados).to all(include(prova: true, feature: 'agente_prova_do_ajuste', agent: agent))
      expect(estado['prova']).to include('status' => 'pronta', 'ok' => 1, 'total' => 2, 'versao_id' => versao_aplicada)
      expect(estado['prova']['perguntas']).to eq(
        [{ 'pergunta' => perguntas[0], 'resposta' => 'Passo para a equipe.', 'equipe' => false },
         { 'pergunta' => perguntas[1], 'resposta' => nil, 'equipe' => true }]
      )
    end

    it 'o juiz recebe só o que entrou (pedido e resumo do Construtor) e cada pergunta com a resposta' do
      agente_responde

      provar!

      expect(juiz).to have_received(:julgar).with(
        pedidos: [{ 'pedido' => fala, 'resumo' => 'Respostas curtas.' }],
        itens: perguntas.map { |pergunta| { 'pergunta' => pergunta, 'resposta' => 'Em até 2 frases.', 'equipe' => false } }
      )
    end

    it 'mexe só na chave da prova: o resto do state fica como estava' do
      agente_responde
      antes = estado.except('prova')

      provar!

      expect(estado.except('prova')).to eq(antes)
    end

    it 'IA indisponível numa resposta: indisponível, sem chamar o juiz' do
      agente_responde(resposta('ok'), resposta(nil, error: 'ai_unavailable'))

      provar!

      expect(estado['prova']['status']).to eq('indisponivel')
      expect(juiz).not_to have_received(:julgar)
    end

    it 'resposta vazia sem passar para a equipe: indisponível' do
      agente_responde(resposta('ok'), resposta(''))

      provar!

      expect(estado['prova']['status']).to eq('indisponivel')
    end

    it 'o juiz falhou: indisponível, nunca um ✓' do
      agente_responde
      allow(juiz).to receive(:julgar).and_return(nil)

      provar!

      expect(estado['prova']).to include('status' => 'indisponivel')
      expect(estado['prova']).not_to have_key('ok')
    end

    it 'erro inesperado (o tempo da resposta estourou no meio): indisponível, sem derrubar o job' do
      allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(Timeout::Error)

      expect { provar! }.not_to raise_error
      expect(estado['prova']['status']).to eq('indisponivel')
    end

    it 'depois do Desfazer, descarta: não responde nem grava' do
      agente_responde
      agent.reload.desfazer_ajuste!(thread: thread.reload)

      provar!

      expect(perguntados).to be_empty
      expect(estado['prova']['status']).to eq('pendente')
    end

    # P3 (revisão): o Desfazer depois da primeira resposta para a prova antes da segunda pergunta e do juiz.
    it 'o Desfazer no meio da prova para na próxima pergunta, sem chamar o juiz' do
      allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
        perguntados << kwargs
        agent.reload.desfazer_ajuste!(thread: Autonomia::Agents::BuildThread.find(thread.id))
        instance_double(Autonomia::Agents::Answerer, answer: resposta('ok'))
      end

      provar!

      expect(perguntados.size).to eq(1)
      expect(juiz).not_to have_received(:julgar)
      expect(estado.dig('ultimo_ajuste', 'desfeito')).to be(true)
      expect(estado['prova']['status']).to eq('pendente')
    end

    it 'o Desfazer durante a última resposta: o juiz não é chamado' do
      chamadas = 0
      allow(Autonomia::Agents::Answerer).to receive(:new) do
        chamadas += 1
        agent.reload.desfazer_ajuste!(thread: Autonomia::Agents::BuildThread.find(thread.id)) if chamadas == perguntas.size
        instance_double(Autonomia::Agents::Answerer, answer: resposta('ok'))
      end

      provar!

      expect(chamadas).to eq(perguntas.size)
      expect(juiz).not_to have_received(:julgar)
    end

    # P2 (revisão): o job repetido depois da prova pronta não gasta nada.
    it 'repetido depois de pronta: não responde, não julga e não regrava' do
      agente_responde
      provar!
      pronta = estado['prova']
      perguntados.clear

      provar!

      expect(perguntados).to be_empty
      expect(juiz).to have_received(:julgar).once
      expect(estado['prova']).to eq(pronta)
    end

    it 'nunca regrava uma prova que já saiu de pendente, nem pela guarda do UPDATE' do
      agente_responde
      provar!
      prova = described_class.new(thread.reload, versao_aplicada)
      allow(prova).to receive(:vigente?).and_return(true)

      expect(prova.send(:gravar!, 'status' => 'indisponivel')).to be(false)
      expect(estado['prova']['status']).to eq('pronta')
    end

    # Revisão (MÉDIA): nada de ✓ falso. O placar conta só as perguntas que tocam a mudança.
    it 'a pergunta que não toca a mudança fica fora do placar' do
      agente_responde
      allow(juiz).to receive(:julgar).and_return(%w[ok nao_testa])

      provar!

      expect(estado['prova']).to include('status' => 'pronta', 'ok' => 1, 'total' => 1)
    end

    it 'nenhuma pergunta toca a mudança: pronta com total 0 (a tela não mostra ✓)' do
      agente_responde
      allow(juiz).to receive(:julgar).and_return(%w[nao_testa nao_testa])

      provar!

      expect(estado['prova']).to include('status' => 'pronta', 'ok' => 0, 'total' => 0)
      expect(estado['prova']['perguntas'].size).to eq(2)
    end

    # A corrida: o Desfazer entra entre a conferência e a escrita. A guarda do próprio UPDATE segura sozinha.
    it 'a escrita é guardada no UPDATE: desfeito depois da conferência, nada é gravado' do
      agente_responde
      prova = described_class.new(thread.reload, versao_aplicada)
      allow(prova).to receive(:vigente?).and_return(true)
      agent.reload.desfazer_ajuste!(thread: thread.reload)

      prova.rodar!

      expect(estado['prova']['status']).to eq('pendente')
    end

    it 'um ajuste novo no meio descarta a prova do anterior' do
      anterior = versao_aplicada
      agente_responde
      thread.append_message!('user', 'Agora mais formal')
      aplicar_ajuste('tone' => 'formal', 'mudancas' => [mudanca('tone', 'Agora mais formal', 'Tom formal.')])

      described_class.new(thread.reload, anterior).rodar!

      expect(perguntados).to be_empty
      expect(estado['prova']).to include('status' => 'pendente', 'versao_id' => versao_aplicada)
    end

    it 'o agente mudou por outro caminho (o Desfazer já não vale): descarta' do
      agente_responde
      agent.reload.update!(tone: 'mudado na gaveta')

      provar!

      expect(perguntados).to be_empty
      expect(estado['prova']['status']).to eq('pendente')
    end
  end

  describe Autonomia::Agents::ProvaDoAjusteJob do
    it 'roda a prova da conversa e da versão pedidas' do
      aplicar_ajuste
      agente_responde

      perform_enqueued_jobs(only: described_class)

      expect(estado['prova']).to include('status' => 'pronta', 'ok' => 2, 'total' => 2)
    end

    it 'fora da Fase 2 não roda nada' do
      aplicar_ajuste
      agente_responde
      Autonomia::Agents::Fase2.desligar!(account)

      perform_enqueued_jobs(only: described_class)

      expect(perguntados).to be_empty
      expect(estado['prova']['status']).to eq('pendente')
    end

    it 'conversa apagada: não levanta' do
      expect { described_class.perform_now(0, 1) }.not_to raise_error
    end
  end
end
