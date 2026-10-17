require 'rails_helper'

# #1428 (tema 6, parte 2) — "Mudar conversando" aplica o pedido inteiro, só ele, e confere. Só no piloto (Fase 2) e só
# no ajuste. O Construtor e a conferência são dublados; quem lê a fala de verdade é o eval pago
# (builder_ajuste_por_lista_eval_spec).
RSpec.describe Autonomia::Agents::Builder do
  let(:account) { conta_da_fase2 }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Hubber', agent_type: 'support', mode: :guided, status: :active, enabled: true,
      instruction: 'Atenda o cliente da corretora com cordialidade.', scaffold: 'andaime', tone: 'cordial',
      greeting: 'Oi! Aqui é o Hubber.', fallback_message: 'Vou confirmar com a equipe.',
      handoff_rule: 'Passe para a equipe quando o cliente pedir.', starter_questions: ['Como funciona?'],
      human_card: 'O Hubber atende os clientes.', config: { 'guardrails' => ['Não invente valores.'], 'voice' => 'masculina',
                                                            'with_knowledge' => false }
    )
  end
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, agent: agent) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:conferente) { instance_double(Autonomia::Agents::ConferenciaDoAjuste) }
  let(:calls) { [] }
  let(:respostas) { [] }
  let(:conferencias) { [] }
  let(:fala) { 'Responda em no máximo 2 frases' }

  # A saída do Construtor no ajuste: a config atual, com o que o teste mudar por cima.
  def saida(overrides = {})
    { 'name' => 'Hubber', 'agent_type' => 'support', 'instruction' => agent.instruction, 'scaffold' => 'andaime',
      'human_card' => agent.human_card, 'greeting' => agent.greeting, 'fallback_message' => agent.fallback_message,
      'handoff_rule' => agent.handoff_rule, 'starter_questions' => agent.starter_questions, 'tone' => agent.tone,
      'guardrails' => ['Não invente valores.'], 'voice' => 'masculina', 'needs_more_info' => false, 'next_question' => '',
      'user_asked_to_close' => false, 'so_pergunta' => false, 'mudancas' => [] }.merge(overrides)
  end

  def tudo_atendido(pedido = fala)
    { 'itens' => [{ 'pedido' => pedido, 'atendido' => true, 'onde' => 'tone e instruction', 'observacao' => 'Entrou.' }],
      'conflitos' => [], 'pergunta' => '', 'pendencias' => [] }
  end

  def faltou(pedido)
    { 'itens' => [{ 'pedido' => pedido, 'atendido' => false, 'onde' => '', 'observacao' => 'Não aparece no agente.' }],
      'conflitos' => [], 'pergunta' => 'Você quer dizer passar para a equipe quando perguntarem preço?',
      'pendencias' => [pedido] }
  end

  before do
    allow(builder).to receive_messages(credential: { api_key: 'chave-de-teste' }, client: fake_client)
    allow(fake_client).to receive(:create) do |**params|
      calls << params
      { text: (respostas.shift || saida).to_json, usage: {}, tools_used: [] }
    end
    allow(Autonomia::Agents::ConferenciaDoAjuste).to receive(:new).and_return(conferente)
    allow(conferente).to receive(:conferir) { conferencias.shift || tudo_atendido }
    thread.append_message!('user', fala)
  end

  def run_turn
    builder.run!(thread.begin_build!)
  end

  def versoes_do_construtor
    agent.instruction_versions.where(reason: 'builder_adjust')
  end

  describe 'fora da Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'manda ao modelo o mesmo pedido de antes: schema sem os campos novos, sem a tabela e sem conferência' do
      respostas << saida('greeting' => 'Olá!')
      esperado = builder.send(:build_input)

      run_turn

      expect(calls.size).to eq(1)
      expect(calls.first[:schema]).to equal(described_class::BUILDER_SCHEMA)
      expect(calls.first[:schema][:schema][:properties].keys).not_to include(:so_pergunta, :mudancas)
      expect(calls.first[:input]).to eq(esperado)
      expect(calls.first[:input].pluck(:role)).not_to include('developer')
      expect(Autonomia::Agents::ConferenciaDoAjuste).not_to have_received(:new)
    end

    it 'aplica como antes, sem lista: o campo que o modelo mudou é gravado e o state não ganha as chaves novas' do
      respostas << saida('greeting' => 'Olá!')

      run_turn

      expect(agent.reload.greeting).to eq('Olá!')
      expect(thread.reload.state).to include('applied' => true)
      expect(thread.state.keys).not_to include('so_pergunta', 'conferencia')
    end
  end

  describe 'no ajuste da Fase 2' do
    it 'manda o schema do ajuste e a tabela de destino num item developer' do
      run_turn

      schema = calls.first[:schema]
      expect(schema).to equal(described_class::AjustePorLista::SCHEMA)
      expect(schema[:schema][:required]).to include('so_pergunta', 'mudancas')
      expect(schema[:schema][:properties][:mudancas][:items][:properties][:campo][:enum])
        .to eq(%w[instruction tone handoff_rule greeting fallback_message starter_questions guardrails human_card name voice])
      expect(calls.first[:input].first).to eq(described_class::AjustePorLista.item_da_tabela)
      expect(calls.first[:instructions]).to equal(described_class::MOTHER_INSTRUCTION)
    end

    describe 'quando a fala é só pergunta (so_pergunta=true)' do
      let(:fala) { 'Me explica o que Hubber faz hoje' }
      let(:resposta) { 'Hoje o Hubber atende os clientes da corretora e passa para a equipe quando pedem.' }

      before { respostas << saida('so_pergunta' => true, 'needs_more_info' => false, 'next_question' => resposta) }

      it 'não aplica, não grava versão e devolve a resposta' do
        expect { run_turn }.not_to(change { [agent.reload.attributes.except('updated_at'), versoes_do_construtor.count] })

        expect(thread.reload.state).to include('needs_more_info' => true, 'next_question' => resposta, 'applied' => false,
                                               'so_pergunta' => true, 'conferencia' => nil)
        expect(thread.messages.last).to include('role' => 'assistant', 'content' => resposta)
        expect(Autonomia::Agents::ConferenciaDoAjuste).not_to have_received(:new)
      end

      it 'a resposta não vira pergunta pendente no turno seguinte nem na próxima sessão' do
        run_turn

        expect(builder.send(:pending_request_context)).to eq('')
        proxima = Autonomia::Agents::BuildThread.create!(account: account, agent: agent)
        proxima.inherit_pending_question!
        expect(proxima.reload.state.to_h['pending_question']).to be_nil
      end
    end

    describe 'quando a lista vem vazia' do
      before { respostas << saida('greeting' => 'Olá, mudei!', 'next_question' => 'Pronto!') }

      it 'não aplica nem diz "Pronto": pergunta o que mudar' do
        run_turn

        expect(agent.reload.greeting).to eq('Oi! Aqui é o Hubber.')
        expect(versoes_do_construtor).to be_empty
        expect(thread.reload.state).to include('needs_more_info' => true, 'applied' => false, 'so_pergunta' => false,
                                               'next_question' => described_class::AjustePorLista::SEM_PEDIDO)
      end
    end

    describe 'quando o próprio modelo pergunta antes de mudar' do
      before do
        respostas << saida('needs_more_info' => true, 'next_question' => 'Duas frases no total ou por mensagem?',
                           'mudancas' => [{ 'pedido' => fala, 'campo' => 'tone', 'resumo' => 'x' }], 'tone' => 'curto')
      end

      it 'não aplica e devolve a pergunta dele' do
        run_turn

        expect(agent.reload.tone).to eq('cordial')
        expect(thread.reload.state).to include('needs_more_info' => true, 'so_pergunta' => false,
                                               'next_question' => 'Duas frases no total ou por mensagem?')
      end
    end

    describe 'quando a instrução listada vem em branco' do
      before do
        respostas << saida('instruction' => '', 'mudancas' => [{ 'pedido' => fala, 'campo' => 'instruction', 'resumo' => 'x' }])
      end

      it 'não grava instrução vazia: pede mais contexto' do
        run_turn

        expect(agent.reload.instruction).to eq('Atenda o cliente da corretora com cordialidade.')
        expect(thread.reload.state['next_question']).to eq(described_class::AjustePorLista::INCOMPLETO)
      end
    end

    describe 'quando o modelo mexe em campos que não listou' do
      before do
        respostas << saida('tone' => 'cordial; responde em no máximo 2 frases', 'greeting' => 'Saudação reescrita',
                           'agent_type' => 'sdr', 'voice' => 'feminina', 'guardrails' => ['Outra regra'],
                           'handoff_rule' => 'Outra regra de passagem', 'name' => 'Outro nome',
                           'mudancas' => [{ 'pedido' => fala, 'campo' => 'tone', 'resumo' => 'Respostas curtas.' }])
      end

      it 'só os campos listados mudam: a saudação, o tipo, a voz e o resto ficam idênticos' do
        antes = agent.attributes.except('tone', 'updated_at')

        run_turn

        agent.reload
        expect(agent.tone).to eq('cordial; responde em no máximo 2 frases')
        expect(agent.attributes.except('tone', 'updated_at')).to eq(antes)
        expect(thread.reload.state['draft_config']).to include('greeting' => 'Oi! Aqui é o Hubber.', 'agent_type' => 'support',
                                                               'tone' => 'cordial; responde em no máximo 2 frases')
      end
    end

    describe 'quando a instrução está na lista' do
      before do
        respostas << saida('instruction' => 'Nova instrução.', 'scaffold' => 'novo andaime', 'human_card' => 'Novo cartão.',
                           'voice' => 'feminina',
                           'mudancas' => [{ 'pedido' => fala, 'campo' => 'instruction', 'resumo' => 'x' },
                                          { 'pedido' => 'voz feminina', 'campo' => 'voice', 'resumo' => 'y' }])
      end

      it 'leva junto o andaime e o cartão; a voz entra no config sem apagar as outras chaves' do
        run_turn

        expect(agent.reload).to have_attributes(instruction: 'Nova instrução.', scaffold: 'novo andaime',
                                                human_card: 'Novo cartão.', tone: 'cordial')
        expect(agent.config).to include('voice' => 'feminina', 'guardrails' => ['Não invente valores.'],
                                        'with_knowledge' => false)
      end
    end

    describe 'com tudo atendido na conferência' do
      let(:mudancas) do
        [{ 'pedido' => fala, 'campo' => 'tone', 'resumo' => 'Respostas curtas.' },
         { 'pedido' => fala, 'campo' => 'instruction', 'resumo' => 'No máximo 2 frases.' }]
      end

      before do
        respostas << saida('tone' => 'cordial e curto', 'instruction' => 'Responda em no máximo 2 frases.',
                           'mudancas' => mudancas, 'next_question' => '')
      end

      it 'chama a conferência com a fala, a lista e o agente antes e depois' do
        run_turn

        expect(Autonomia::Agents::ConferenciaDoAjuste).to have_received(:new).with(account: account, credential: anything).once
        expect(conferente).to have_received(:conferir).once.with(
          pedido: fala, mudancas: mudancas,
          antes: hash_including('tone' => 'cordial', 'instruction' => 'Atenda o cliente da corretora com cordialidade.',
                                'greeting' => 'Oi! Aqui é o Hubber.', 'voice' => 'masculina'),
          depois: hash_including('tone' => 'cordial e curto', 'instruction' => 'Responda em no máximo 2 frases.')
        )
      end

      it 'guarda o resultado no state e na versão builder_adjust, e fecha sem pergunta' do
        run_turn

        expect(thread.reload.state).to include('needs_more_info' => false, 'applied' => true, 'so_pergunta' => false,
                                               'conferencia' => tudo_atendido.merge('correcao' => false))
        versao = versoes_do_construtor.sole
        expect(versao.metadata).to include('pedido' => fala, 'mudancas' => mudancas, 'conferencia' => tudo_atendido)
        expect(versao.metadata['agente']).to include('tone' => 'cordial e curto')
        expect(calls.size).to eq(1)
      end
    end

    describe 'quando a conferência acha falta' do
      let(:preco) { 'preço passa para a equipe' }
      let(:fala) { "Responda em no máximo 2 frases e #{preco}" }

      before do
        respostas << saida('tone' => 'cordial e curto',
                           'mudancas' => [{ 'pedido' => 'no máximo 2 frases', 'campo' => 'tone', 'resumo' => 'Curto.' }])
        conferencias << faltou(preco)
      end

      it 'faz UMA correção com o aviso do que faltou e confere de novo' do
        respostas << saida('handoff_rule' => 'Passe para a equipe quando perguntarem preço.',
                           'mudancas' => [{ 'pedido' => preco, 'campo' => 'handoff_rule', 'resumo' => 'Preço vai à equipe.' }])
        conferencias << tudo_atendido(preco)

        run_turn

        expect(calls.size).to eq(2)
        aviso = calls.last[:input].last
        expect(aviso[:role]).to eq('developer')
        expect(aviso[:content].first[:text]).to include('faltou aplicar', preco)
        expect(calls.last[:input]).to include(hash_including(content: [hash_including(text: a_string_including('tone: cordial e curto'))]))
        expect(agent.reload).to have_attributes(tone: 'cordial e curto', handoff_rule: 'Passe para a equipe quando perguntarem preço.')
        expect(conferente).to have_received(:conferir).twice
      end

      it 'com a correção atendida, fecha sem pergunta e cada versão leva a sua conferência' do
        respostas << saida('handoff_rule' => 'Passe para a equipe quando perguntarem preço.',
                           'mudancas' => [{ 'pedido' => preco, 'campo' => 'handoff_rule', 'resumo' => 'Preço vai à equipe.' }])
        conferencias << tudo_atendido(preco)

        run_turn

        expect(thread.reload.state).to include('needs_more_info' => false, 'applied' => true)
        expect(thread.state['conferencia']).to include('correcao' => true, 'pendencias' => [])
        expect(versoes_do_construtor.order(:id).map { |versao| versao.metadata['conferencia'] })
          .to eq([faltou(preco), tudo_atendido(preco)])
      end

      it 'se ainda faltar, vira pergunta ao dono e o que entrou fica aplicado' do
        respostas << saida('handoff_rule' => 'Outra coisa.',
                           'mudancas' => [{ 'pedido' => preco, 'campo' => 'handoff_rule', 'resumo' => 'x' }])
        conferencias << faltou(preco)

        run_turn

        expect(calls.size).to eq(2)
        expect(agent.reload.tone).to eq('cordial e curto')
        estado = thread.reload.state
        expect(estado).to include('needs_more_info' => true, 'applied' => true, 'so_pergunta' => false)
        expect(estado['next_question'])
          .to eq("Não consegui aplicar: #{preco}. Você quer dizer passar para a equipe quando perguntarem preço?")
        expect(estado['conferencia']).to include('correcao' => true, 'pendencias' => [preco])
        expect(thread.messages.last).to include('role' => 'assistant', 'content' => estado['next_question'])
      end

      it 'se a correção não aplicar nada, vira pergunta sem segunda conferência' do
        respostas << saida('needs_more_info' => true, 'next_question' => 'Qual equipe?')

        run_turn

        expect(conferente).to have_received(:conferir).once
        expect(thread.reload.state).to include('needs_more_info' => true, 'applied' => true)
        expect(thread.state['next_question']).to start_with("Não consegui aplicar: #{preco}.")
        expect(thread.state['conferencia']).to include('correcao' => false)
      end
    end

    describe 'quando a conferência está indisponível' do
      before do
        respostas << saida('tone' => 'curto', 'mudancas' => [{ 'pedido' => fala, 'campo' => 'tone', 'resumo' => 'x' }])
        conferencias << Autonomia::Agents::ConferenciaDoAjuste::INDISPONIVEL.dup
      end

      it 'o que entrou fica aplicado, sem correção, e o state registra a falta da conferência' do
        run_turn

        expect(calls.size).to eq(1)
        expect(agent.reload.tone).to eq('curto')
        expect(thread.reload.state['conferencia']).to include('erro' => 'conferencia_indisponivel')
      end
    end

    describe 'as recusas continuam' do
      before do
        respostas << saida('tone' => 'curto', 'mudancas' => [{ 'pedido' => fala, 'campo' => 'tone', 'resumo' => 'x' }])
      end

      it 'a Lia (insurance_quote) nunca muda' do
        lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote',
                                               instruction: 'retrato do nascimento', tone: 'cordial')
        thread.update!(agent: lia)

        expect { run_turn }.to raise_error(Autonomia::Agents::Agent::InstrucaoMantida)
        expect(lia.reload.tone).to eq('cordial')
        expect(Autonomia::Agents::ConferenciaDoAjuste).not_to have_received(:new)
      end

      it 'agente em modo manual é recusado' do
        agent.update!(mode: :manual)

        expect { run_turn }.to raise_error(Autonomia::Agents::Agent::ModoManual)
        expect(agent.reload.tone).to eq('cordial')
        expect(Autonomia::Agents::ConferenciaDoAjuste).not_to have_received(:new)
      end
    end
  end
end
