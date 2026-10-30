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

  def resposta(texto, handoff: false, error: nil, base: [])
    usados = base.each_with_index.map { |conteudo, indice| { id: indice + 1, content: conteudo, source: 'manual' } }
    Autonomia::Agents::AnswerResult.new(reply: texto, confidence: 0.9, handoff: { should: handoff, reason: nil }, error: error,
                                        used_knowledge: usados)
  end

  def provar!
    described_class.new(thread.reload, versao_aplicada).rodar!
  end

  # O que o juiz devolve: o veredito da pergunta e um teste por pedido testado, com o mesmo veredito (o primeiro pedido,
  # salvo quando a pergunta não testa nada).
  def vereditos(*notas, pedidos: [0])
    notas.map do |nota|
      testes = nota == 'nao_testa' ? [] : pedidos.map { |posicao| { 'pedido' => posicao, 'veredito' => nota } }
      { 'veredito' => nota, 'testes' => testes }
    end
  end

  before do
    allow(Autonomia::Agents::JuizDaProva).to receive(:new).and_return(juiz)
    allow(juiz).to receive(:julgar) { |itens:, **| vereditos(*Array.new(itens.size, 'ok')) }
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

    # Forense do t6d (P1): cada mensagem de prova diz qual pedido testa, com o texto de `mudancas`.
    it 'a mensagem de prova vem com o pedido que ela testa e a prova pendente guarda os dois' do
      aplicar_ajuste('perguntas_de_prova' => [{ 'mensagem' => 'Oi, tudo bem?', 'pedido' => fala },
                                              { 'mensagem' => 'Quais seguros vocês têm?', 'pedido' => "#{fala}." }])

      expect(estado.dig('prova', 'perguntas')).to eq([{ 'pergunta' => 'Oi, tudo bem?', 'pedido' => fala },
                                                      { 'pergunta' => 'Quais seguros vocês têm?', 'pedido' => fala }])
      expect(Autonomia::Agents::ProvaDoAjusteJob).to have_been_enqueued.with(thread.id, versao_aplicada)
    end

    # Compatibilidade: o formato antigo (só o texto) gravado num ajuste em curso antes do deploy continua valendo.
    it 'perguntas gravadas no formato antigo (só texto) viram a prova pendente igual a antes' do
      expect(described_class.pendente(agent, 'perguntas_de_prova' => perguntas, 'versao_id' => 1)['perguntas'])
        .to eq(perguntas.map { |pergunta| { 'pergunta' => pergunta } })
      expect(described_class.pendente(agent, 'perguntas_de_prova' => [{ 'pergunta' => 'Oi?', 'pedido' => fala }],
                                             'versao_id' => 1)['perguntas']).to eq([{ 'pergunta' => 'Oi?', 'pedido' => fala }])
    end

    # Revisão do t6d (BAIXO): a prova pendente aguenta Hash cru do modelo ({mensagem, pedido}), Hash sem texto e lixo.
    it 'pendente lê {mensagem, pedido}, descarta Hash sem texto e o que não é texto; sem nenhuma, sem prova' do
      dados = { 'versao_id' => 1, 'perguntas_de_prova' => [{ 'mensagem' => 'Tem loja?', 'pedido' => fala }, { 'pedido' => fala },
                                                           { 'pergunta' => '' }, 7, nil, 'Oi?', { 'pergunta' => 'Abre?' }] }

      expect(described_class.pendente(agent, dados)['perguntas']).to eq([{ 'pergunta' => 'Tem loja?', 'pedido' => fala },
                                                                         { 'pergunta' => 'Oi?' },
                                                                         { 'pergunta' => 'Abre?' }])
      expect(described_class.pendente(agent, 'versao_id' => 1, 'perguntas_de_prova' => [{ 'pedido' => fala }])).to be_nil
    end
  end

  # Revisão do t6d (MÉDIO 2): o pedido declarado em cada mensagem é usado. Pedido sem nenhuma mensagem: sem prova
  # completa, antes de olhar o juiz. O pedido fica gravado em cada item.
  describe '#rodar! com o pedido declarado em cada mensagem' do
    let(:preco) { 'preço passa para a equipe' }

    def ajustar_com(*declarados)
      aplicar_ajuste('handoff_rule' => 'Preço vai à equipe.',
                     'mudancas' => [mudanca('tone', fala, 'Respostas curtas.'), mudanca('handoff_rule', preco, 'Preço vai à equipe.')],
                     'perguntas_de_prova' => declarados.each_with_index.map { |pedido, i| { 'mensagem' => "Pergunta #{i}?", 'pedido' => pedido } })
      agente_responde
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', pedidos: [0, 1]) + vereditos('ok', pedidos: [0, 1]))
    end

    it 'um pedido sem nenhuma mensagem: sem prova completa, mesmo com o juiz dando os dois testados' do
      ajustar_com(fala, fala)

      provar!

      expect(estado['prova']).to include('ok' => 2, 'total' => 2, 'completa' => false)
      expect(estado.dig('prova', 'perguntas').pluck('pedido')).to eq([fala, fala])
    end

    # Revisão 2 do t6d (MÉDIO 1): a dispensa vale só quando TODAS as mensagens vieram no formato antigo (só texto).
    it 'uma mensagem cujo pedido não bateu com a lista conta como não declarada: sem prova completa' do
      ajustar_com(fala, preco, 'outro pedido')
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', pedidos: [0, 1]) * 3)

      provar!

      expect(estado['prova']).to include('completa' => false)
      expect(estado.dig('prova', 'perguntas').pluck('pedido')).to eq([fala, preco, nil])
    end

    it 'mensagens misturadas (texto puro e com pedido): o pedido sem mensagem deixa a prova incompleta' do
      aplicar_ajuste('handoff_rule' => 'Preço vai à equipe.',
                     'mudancas' => [mudanca('tone', fala, 'Respostas curtas.'), mudanca('handoff_rule', preco, 'Preço vai à equipe.')],
                     'perguntas_de_prova' => ['Oi?', { 'mensagem' => 'Tudo bem?', 'pedido' => fala }])
      agente_responde
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', pedidos: [0, 1]) * 2)

      provar!

      expect(estado['prova']).to include('completa' => false)
    end

    it 'cada pedido com a sua mensagem: completa, e o juiz recebe o pedido de cada item' do
      ajustar_com(fala, preco)

      provar!

      expect(estado['prova']).to include('completa' => true)
      expect(juiz).to have_received(:julgar) { |itens:, **| expect(itens.pluck('pedido')).to eq([fala, preco]) }
    end
  end

  # Forense do t6d (P1): a escola perguntou do "teste de nivelamento", que não está escrito em campo nenhum, e o agente
  # respondeu a mensagem fixa (sem base e sem ferramenta). A descrição diz como escolher a mensagem para cada pedido.
  describe '.perguntas e a descrição do campo' do
    let(:lista) { [mudanca('tone', 'sem emoji'), mudanca('instruction', 'mais curto')] }

    it 'lê {mensagem, pedido}: o pedido vira o texto de mudancas, e pedido que não está na lista fica sem pedido' do
      lido = described_class.perguntas(
        'mudancas' => lista,
        'perguntas_de_prova' => [{ 'mensagem' => ' Oi! ', 'pedido' => 'sem emoji' },
                                 { 'mensagem' => 'Quais formas de pagamento?', 'pedido' => 'mais curto.' },
                                 { 'mensagem' => 'Tem loja física?', 'pedido' => 'outro pedido' },
                                 { 'mensagem' => 'Quarta?', 'pedido' => 'sem emoji' }]
      )

      expect(lido).to eq([{ 'pergunta' => 'Oi!', 'pedido' => 'sem emoji' },
                          { 'pergunta' => 'Quais formas de pagamento?', 'pedido' => 'mais curto' },
                          { 'pergunta' => 'Tem loja física?', 'pedido' => nil }])
    end

    it 'mensagem em branco, repetida ou que não é texto fica fora; o formato antigo (só texto) ainda é lido' do
      lido = described_class.perguntas(
        'mudancas' => lista,
        'perguntas_de_prova' => [{ 'mensagem' => '', 'pedido' => 'sem emoji' }, { 'mensagem' => 7, 'pedido' => 'sem emoji' },
                                 'Oi!', { 'mensagem' => 'Oi!', 'pedido' => 'sem emoji' }, nil]
      )

      expect(lido).to eq([{ 'pergunta' => 'Oi!' }])
    end

    # Revisão do t6d (ALTO 1): a prova roda como no Testar, COM a base quando ligada; só sem ferramenta.
    it 'a descrição: prova sem ferramenta e com a base, fato escrito nos campos sem vir na mensagem, 2 tipos para forma' do
      descricao = described_class::PERGUNTAS_DESCRIPTION
      expect(descricao).to include('A prova roda sem ferramenta, como no Testar', 'e pela base de conhecimento, quando ligada',
                                   'um fato ESCRITO nos campos do agente',
                                   'prefira o human_card, a saudacao e os guardrails', 'a mensagem nao traz o fato',
                                   'nao so o nome do assunto', '2 mensagens de tipos diferentes', 'um cumprimento',
                                   'algo que nao esta em nenhum campo do agente nem na base')
      expect(descricao).not_to include('sem base de conhecimento')
      # Tema 6: a prova roda como o atendimento, sem o portão; a falta de dado não vira mais a mensagem fixa.
      expect(descricao).not_to include('mensagem fixa')
    end

    # Série 2 do t6d anulada (escola): "Qual é o nome da escola?" tem resposta quase igual antes e depois do pedido e não
    # mostra o tom. Para pedido de forma, a mensagem puxa uma resposta em que a forma aparece; o exemplo é de outro ramo.
    it 'a descrição: em pedido de forma, a resposta mostra a forma numa frase ao cliente; dado curto não serve' do
      descricao = described_class::PERGUNTAS_DESCRIPTION
      expect(descricao).to include('em todo pedido de forma, cada mensagem puxa uma resposta em que a forma aparece',
                                   'com ao menos uma frase dirigida ao cliente',
                                   'pergunta de dado curto (um nome, um endereco) nao serve para pedido de forma',
                                   'a resposta sai quase igual antes e depois do pedido', 'numa padaria')
      expect(descricao).not_to include('escola')
    end

    it 'o item do schema é {mensagem, pedido}, estrito' do
      item = described_class::PERGUNTA_DE_PROVA
      expect(item).to include(type: 'object', additionalProperties: false, required: %w[mensagem pedido])
      expect(item[:properties].keys).to eq(%i[mensagem pedido])
    end
  end

  describe '#rodar!' do
    before { aplicar_ajuste }

    it 'responde cada pergunta em modo prova, com a feature própria, e grava pronta com o veredito do juiz' do
      agente_responde(resposta('Passo para a equipe.'), resposta(nil, handoff: true))
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', 'nao'))

      provar!

      expect(perguntados.pluck(:query)).to eq(perguntas)
      expect(perguntados).to all(include(prova: true, trust_instruction: true, feature: 'agente_prova_do_ajuste', agent: agent))
      expect(estado['prova']).to include('status' => 'pronta', 'ok' => 1, 'total' => 2, 'versao_id' => versao_aplicada,
                                         'completa' => true)
      expect(estado['prova']['perguntas']).to eq(
        [{ 'pergunta' => perguntas[0], 'resposta' => 'Passo para a equipe.', 'equipe' => false, 'veredito' => 'ok',
           'testes' => [{ 'pedido' => 0, 'veredito' => 'ok' }] },
         { 'pergunta' => perguntas[1], 'resposta' => nil, 'equipe' => true, 'veredito' => 'nao',
           'testes' => [{ 'pedido' => 0, 'veredito' => 'nao' }] }]
      )
    end

    # Revisão do t6d (ALTO 1): a prova roda com a base; o juiz recebe os trechos que a resposta usou, com teto.
    it 'os trechos da base que a resposta usou vão ao juiz e ficam na prova, com teto de tamanho e de quantidade' do
      maior_pedaco = [*Autonomia::Agents::Config::CHUNK_PROFILES.values, Autonomia::Agents::Config::DEFAULT_CHUNK_PROFILE]
                     .pluck(:max).max
      expect(described_class::TRECHO_MAX_CHARS).to eq(maior_pedaco)
      longo = 'x' * (described_class::TRECHO_MAX_CHARS + 50)
      agente_responde(resposta('A aula é às 19h.', base: ['Aulas às 19h.', longo, 'c', 'd']), resposta('Oi.'))

      provar!

      trechos = ['Aulas às 19h.', "#{'x' * (described_class::TRECHO_MAX_CHARS - 3)}...", 'c']
      expect(juiz).to have_received(:julgar) do |itens:, **|
        expect(itens.first['trechos']).to eq(trechos)
        expect(itens.last).not_to have_key('trechos')
      end
      expect(estado.dig('prova', 'perguntas', 0, 'trechos')).to eq(trechos)
    end

    it 'o juiz recebe só o que entrou (pedido e resumo do Construtor) e cada pergunta com a resposta' do
      agente_responde

      provar!

      expect(juiz).to have_received(:julgar).with(
        pedidos: [{ 'numero' => 1, 'pedido' => fala, 'o_que_mudou' => ['Respostas curtas.'] }],
        itens: perguntas.map { |pergunta| { 'pergunta' => pergunta, 'resposta' => 'Em até 2 frases.', 'equipe' => false } },
        agente: anything
      )
    end

    # Forense do t6d (P2): o juiz precisa saber o que o agente tem escrito para julgar "quando não souber" e a forma.
    it 'o juiz recebe os campos do agente que importam para julgar, sem o nome, o cartão nem a voz' do
      agente_responde

      provar!

      expect(juiz).to have_received(:julgar) do |agente:, **|
        expect(agente).to eq('instruction' => agent.instruction, 'tone' => agent.reload.tone, 'greeting' => agent.greeting,
                             'fallback_message' => agent.fallback_message, 'handoff_rule' => agent.handoff_rule,
                             'guardrails' => ['Não invente valores.'])
      end
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

    it 'falha de rede da IA: indisponível, sem derrubar o job' do
      allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(Net::ReadTimeout)

      expect { provar! }.not_to raise_error
      expect(estado['prova']['status']).to eq('indisponivel')
    end

    it 'erro do provedor: indisponível' do
      allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

      provar!

      expect(estado['prova']['status']).to eq('indisponivel')
    end

    # Revisão crítica: o que não é falha da IA sobe para o rastreio do job, sem virar "indisponível" em silêncio.
    it 'erro de código sobe e a prova fica pendente' do
      allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(NoMethodError)

      expect { provar! }.to raise_error(NoMethodError)
      expect(estado['prova']['status']).to eq('pendente')
    end

    # W3: a prova pendente além da validade (o job atrasou na fila) não gasta nada.
    it 'W3: pendente mais velha que a validade: não responde, não julga e não grava' do
      agente_responde
      travel_to((described_class::VALIDADE_DO_PENDENTE + 1.minute).from_now) { provar! }

      expect(perguntados).to be_empty
      expect(juiz).not_to have_received(:julgar)
      expect(estado['prova']['status']).to eq('pendente')
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
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', 'nao_testa'))

      provar!

      expect(estado['prova']).to include('status' => 'pronta', 'ok' => 1, 'total' => 1)
    end

    it 'nenhuma pergunta toca a mudança: pronta com total 0 (a tela não mostra ✓)' do
      agente_responde
      allow(juiz).to receive(:julgar).and_return(vereditos('nao_testa', 'nao_testa'))

      provar!

      expect(estado['prova']).to include('status' => 'pronta', 'ok' => 0, 'total' => 0, 'completa' => false)
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

  # Revisão do t6d (MÉDIO): ajuste misto. O ✓ só sai quando cada pedido tem ao menos uma pergunta que o testa.
  describe '#rodar! num ajuste com dois pedidos' do
    let(:preco) { 'preço passa para a equipe' }

    before do
      aplicar_ajuste('handoff_rule' => 'Preço vai à equipe.',
                     'mudancas' => [mudanca('tone', fala, 'Respostas curtas.'), mudanca('instruction', fala, 'No máximo 2 frases.'),
                                    mudanca('handoff_rule', preco, 'Preço vai à equipe.')])
      agente_responde
    end

    it 'o juiz recebe um item por pedido, numerado, com o que mudou em cada um' do
      provar!

      expect(juiz).to have_received(:julgar).with(
        pedidos: [{ 'numero' => 1, 'pedido' => fala, 'o_que_mudou' => ['Respostas curtas.', 'No máximo 2 frases.'] },
                  { 'numero' => 2, 'pedido' => preco, 'o_que_mudou' => ['Preço vai à equipe.'] }],
        itens: anything, agente: anything
      )
    end

    it 'sem nenhuma pergunta de preço: tudo ok, mas sem prova completa' do
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', 'ok', pedidos: [0]))

      provar!

      expect(estado['prova']).to include('status' => 'pronta', 'ok' => 2, 'total' => 2, 'completa' => false)
    end

    it 'com uma pergunta para cada pedido: completa' do
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', pedidos: [0]) + vereditos('ok', pedidos: [1]))

      provar!

      expect(estado['prova']).to include('ok' => 2, 'total' => 2, 'completa' => true)
    end

    # Revisão do t6d (MÉDIO 1): um item da correção que saiu por texto de pedido fora da lista nunca some em silêncio.
    it 'com item descartado na correção, a prova não sai completa' do
      thread.update!(state: thread.state.deep_merge('ultimo_ajuste' => { 'conferencia' => { 'itens_descartados' => 1 } }))
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', pedidos: [0, 1]) + vereditos('ok', pedidos: [0, 1]))

      provar!

      expect(estado['prova']).to include('ok' => 2, 'total' => 2, 'completa' => false)
    end

    # t6d R4/R5: a resposta curta e sem emoji testa os dois pedidos de uma vez.
    it 'uma resposta que testa os dois pedidos, os dois ok: completa e ok' do
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', pedidos: [0, 1]) + vereditos('nao_testa'))

      provar!

      expect(estado['prova']).to include('ok' => 1, 'total' => 1, 'completa' => true)
      expect(estado['prova']['perguntas'].first['testes'].pluck('pedido')).to eq([0, 1])
    end

    # Revisão do t6d (ALTO): curta e com emoji. O pedido do emoji foi testado e falhou: completa, mas a pergunta é nao.
    it 'uma resposta ok num pedido e nao no outro: a pergunta conta como nao, sem ✓' do
      testes = [{ 'pedido' => 0, 'veredito' => 'ok' }, { 'pedido' => 1, 'veredito' => 'nao' }]
      allow(juiz).to receive(:julgar).and_return([{ 'veredito' => 'nao', 'testes' => testes }] + vereditos('nao_testa'))

      provar!

      expect(estado['prova']).to include('ok' => 0, 'total' => 1, 'completa' => true)
    end

    it 'pedido testado com nao conta como coberto, mas o placar mostra a falha' do
      allow(juiz).to receive(:julgar).and_return(vereditos('nao', pedidos: [0]) + vereditos('ok', pedidos: [1]))

      provar!

      expect(estado['prova']).to include('ok' => 1, 'total' => 2, 'completa' => true)
    end
  end

  # Revisão do t6d (MÉDIOS): os pedidos da prova são os mesmos grupos do cartão, e com um pedido só não há o que cobrir.
  describe '#rodar! com os grupos do cartão' do
    it 'o mesmo pedido no tom e na instrução, com ponto final só num deles, é 1 pedido e a prova sai completa' do
      aplicar_ajuste('mudancas' => [mudanca('tone', fala, 'Respostas curtas.'),
                                    mudanca('instruction', "#{fala}.", 'No máximo 2 frases.')])
      agente_responde
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', 'ok', pedidos: [0]))

      provar!

      expect(juiz).to have_received(:julgar).with(
        pedidos: [{ 'numero' => 1, 'pedido' => fala, 'o_que_mudou' => ['Respostas curtas.', 'No máximo 2 frases.'] }],
        itens: anything, agente: anything
      )
      expect(estado['prova']).to include('ok' => 2, 'total' => 2, 'completa' => true)
    end

    it 'com um pedido só, uma pergunta que o testa basta' do
      aplicar_ajuste
      agente_responde
      allow(juiz).to receive(:julgar).and_return(vereditos('ok', 'nao_testa'))

      provar!

      expect(estado['prova']).to include('ok' => 1, 'total' => 1, 'completa' => true)
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

    # Revisão: sem nova tentativa. A prova repetida gastaria de novo e chegaria depois que a tela desistiu.
    it 'não reenfileira: retry desligado no Sidekiq e nada volta para a fila quando o erro sobe' do
      aplicar_ajuste
      clear_enqueued_jobs
      allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(NoMethodError)

      expect(described_class.get_sidekiq_options['retry']).to be(false)
      expect { described_class.perform_now(thread.id, versao_aplicada) }.to raise_error(NoMethodError)
      expect(described_class).not_to have_been_enqueued
    end

    it 'erro de rede (SSL, host ou rede inalcançável) vira indisponível' do
      aplicar_ajuste
      allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(OpenSSL::SSL::SSLError)

      described_class.perform_now(thread.id, versao_aplicada)

      expect(estado['prova']['status']).to eq('indisponivel')
      expect(Autonomia::Agents::ProvaDoAjuste::FALHAS_DA_IA).to include(Errno::EHOSTUNREACH, Errno::ENETUNREACH)
    end
  end
end
