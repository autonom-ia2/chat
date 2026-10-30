require 'rails_helper'

# #1428 (tema 6, parte 3) — o resultado do último ajuste na tela: um pedido por linha, o que o dono não pediu à parte e
# nunca o campo, a conferência ou a instrução.
RSpec.describe Autonomia::Agents::ResultadoDoAjuste do
  let(:account) { conta_da_fase2 }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Hubber', agent_type: 'support', instruction: 'Instrução secreta.',
                                     scaffold: 'andaime secreto')
  end
  # A versão de antes e a da aplicação (o agente como está agora).
  let(:ultimo) do
    { 'versao_antes_id' => agent.send(:gravar_versao!, 'base', nil).id, 'versao_id' => agent.send(:gravar_versao!, 'builder_adjust', nil).id }
  end

  def item(campo, pedido, resumo, atendido: true, pedido_pelo_dono: true)
    { 'campo' => campo, 'pedido' => pedido, 'resumo' => resumo, 'atendido' => atendido, 'pedido_pelo_dono' => pedido_pelo_dono }
  end

  def resultado(conferencia, extra = {})
    thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent, status: :ready,
                                                    state: { 'applied' => true, 'conferencia' => conferencia,
                                                             'ultimo_ajuste' => ultimo.merge('conferencia' => conferencia) }.merge(extra))
    described_class.new(thread).to_h
  end

  it 'agrupa pelo pedido: aplicado com o resumo do principal, não aplicado com o pedido' do
    saida = resultado('itens' => [item('tone', '2 frases', 'Respostas curtas.'),
                                  item('instruction', '2 frases', 'No máximo 2 frases.'),
                                  item('handoff_rule', 'preço com a equipe.', 'Preço vai à equipe.', atendido: false)])

    expect(saida[:itens]).to eq([{ estado: 'aplicado', texto: 'Respostas curtas.' },
                                 { estado: 'nao_aplicado', texto: 'preço com a equipe' }])
    expect(saida).to include(conferido: true, faltou_fora: false, desfeito: false, desfeito_sozinho: false)
  end

  # Revisão do t6d (MÉDIO): o mesmo pedido, com e sem ponto final, é uma linha só (o grupo que a prova também usa).
  it 'o mesmo pedido com e sem ponto final é uma linha só' do
    saida = resultado('itens' => [item('tone', '2 frases', 'Respostas curtas.'), item('instruction', '2 frases.', 'No máximo 2 frases.')])

    expect(saida[:itens]).to eq([{ estado: 'aplicado', texto: 'Respostas curtas.' }])
  end

  it 'o destino secundário pela tabela entra no grupo do pedido principal' do
    saida = resultado('itens' => [item('tone', 'mais curto', 'Respostas curtas.'),
                                  item('instruction', 'regra de tamanho', 'No máximo 2 frases.', atendido: false,
                                                                                                 pedido_pelo_dono: false)])

    expect(saida[:itens]).to eq([{ estado: 'nao_aplicado', texto: 'mais curto' }])
  end

  it 'o que o dono não pediu e mudou vai à parte; o que ele não pediu e ficou igual não aparece' do
    nao_pedido = item('greeting', 'saudação', 'Saudação nova.', pedido_pelo_dono: false)
    igual = item('fallback_message', 'fallback', 'Igual.', pedido_pelo_dono: false)
    saida = resultado('itens' => [item('tone', 'mais curto', 'Respostas curtas.'), nao_pedido, igual],
                      'sem_pedido' => [nao_pedido])

    expect(saida[:itens]).to eq([{ estado: 'aplicado', texto: 'Respostas curtas.' },
                                 { estado: 'sem_pedido', texto: 'Saudação nova' }])
  end

  it 'quando o código desfez tudo o que não foi pedido, diz isso e não lista nada' do
    nao_pedido = item('greeting', 'saudação', 'Saudação nova.', pedido_pelo_dono: false)
    saida = resultado({ 'itens' => [nao_pedido], 'desfeito' => { 'campos' => ['greeting'], 'ok' => true } },
                      'applied' => false, 'ultimo_ajuste' => nil)

    expect(saida).to include(itens: [], desfeito_sozinho: true, pode_desfazer: false)
  end

  it 'quando o código não conseguiu desfazer o que não foi pedido, ele aparece como mudado' do
    nao_pedido = item('greeting', 'saudação', 'Saudação nova.', pedido_pelo_dono: false)
    saida = resultado('itens' => [nao_pedido], 'desfeito' => { 'campos' => ['greeting'], 'ok' => false })

    expect(saida).to include(itens: [{ estado: 'sem_pedido', texto: 'Saudação nova' }], desfeito_sozinho: false)
    expect(described_class.mostrar?(agent.build_threads.last)).to be(false)
  end

  it 'sem a conferência (provedor falhou), não diz que conferiu' do
    saida = resultado(Autonomia::Agents::ConferenciaDoAjuste::INDISPONIVEL.merge('correcao' => false))

    expect(saida).to include(conferido: false, itens: [])
  end

  it 'sem a marca dos itens (a 2ª conferência passou do teto), não diz que conferiu' do
    saida = resultado('itens' => [{ 'campo' => 'tone', 'pedido' => 'curto', 'resumo' => 'Curto.' }], 'falta' => false)

    expect(saida).to include(conferido: false, itens: [{ estado: 'aplicado', texto: 'Curto.' }])
  end

  it 'avisa o pedido da fala que ficou fora da lista' do
    expect(resultado('itens' => [item('tone', 'curto', 'Curto.')], 'faltou_fora_da_lista' => true)).to include(faltou_fora: true)
  end

  it 'pode desfazer enquanto o agente é o que o ajuste deixou; depois de outra mudança, não' do
    conferencia = { 'itens' => [item('tone', 'curto', 'Curto.')] }
    expect(resultado(conferencia)[:pode_desfazer]).to be(true)

    agent.update!(greeting: 'Editado.')
    expect(resultado(conferencia)[:pode_desfazer]).to be(false)
  end

  it 'não oferece desfazer sem a versão de antes' do
    saida = resultado({ 'itens' => [item('tone', 'curto', 'Curto.')] }, 'ultimo_ajuste' => ultimo.merge('versao_antes_id' => nil))

    expect(saida[:pode_desfazer]).to be(false)
    expect(described_class.ultima_mudanca_desfazivel(agent)).to be_nil
  end

  it 'não oferece desfazer em agente manual' do
    agent.update_columns(mode: Autonomia::Agents::Agent.modes[:manual]) # rubocop:disable Rails/SkipsModelValidations

    expect(resultado('itens' => [item('tone', 'curto', 'Curto.')])[:pode_desfazer]).to be(false)
  end

  it 'depois de desfeito, diz desfeito e não oferece de novo' do
    saida = resultado({ 'itens' => [item('tone', 'curto', 'Curto.')] }, 'ultimo_ajuste' => ultimo.merge('desfeito' => true))

    expect(saida).to include(desfeito: true, pode_desfazer: false)
  end

  it 'nunca leva o campo, a marca da conferência, a instrução ou o andaime' do
    json = resultado('itens' => [item('instruction', 'curto', 'Curto.'), item('tone', 'x', 'Y.', atendido: false)]).to_json

    expect(json).not_to include('campo', 'instruction', 'pedido_pelo_dono', 'atendido', 'Instrução secreta', 'andaime')
  end

  describe '.ultima_mudanca_desfazivel' do
    it 'só os aplicados, no máximo 3, sem o ponto final' do
      resultado('itens' => [item('tone', 'a', 'Um.'), item('greeting', 'b', 'Dois.', atendido: false),
                            item('handoff_rule', 'c', 'Três.'), item('fallback_message', 'd', 'Quatro.'),
                            item('human_card', 'e', 'Cinco.')])
      thread = agent.build_threads.last

      expect(described_class.ultima_mudanca_desfazivel(agent.reload))
        .to eq(thread_id: thread.id, linhas: %w[Um Três Quatro], sem_pedido: [])
    end

    it 'depois de uma pergunta na conversa (sem conferência no state), lê o ajuste guardado, com o não pedido' do
      nao_pedido = item('greeting', 'saudação', 'Saudação nova.', pedido_pelo_dono: false)
      guardada = { 'itens' => [item('tone', 'a', 'Curto.'), nao_pedido], 'sem_pedido' => [nao_pedido] }
      resultado(nil, 'ultimo_ajuste' => ultimo.merge('conferencia' => guardada))

      expect(described_class.ultima_mudanca_desfazivel(agent.reload)).to include(linhas: ['Curto'], sem_pedido: ['Saudação nova'])
    end
  end

  describe '.mostrar?' do
    it 'só com a conversa parada, a conferência no state e o piloto ligado' do
      thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent, status: :ready,
                                                      state: { 'conferencia' => { 'itens' => [] } })
      expect(described_class.mostrar?(thread)).to be(true)

      thread.update!(status: :processing)
      expect(described_class.mostrar?(thread)).to be(false)

      thread.update!(status: :ready)
      Autonomia::Agents::Fase2.desligar!(account)
      expect(described_class.mostrar?(thread.reload)).to be(false)
    end
  end

  # #1428 (entrega B) — a prova só é a do ajuste no cartão, não desfeito; pendente velha vira indisponível.
  describe '#prova' do
    let(:conferencia) { { 'itens' => [item('tone', 'mais curto', 'Respostas curtas.')] } }

    def prova_com(dados, extra = {})
      resultado(conferencia, { 'prova' => { 'versao_id' => ultimo['versao_id'], 'perguntas' => [{ 'pergunta' => 'Oi?' }] }.merge(dados) }
                               .merge(extra))[:prova]
    end

    it 'pendente recente: pendente com o total' do
      expect(prova_com('status' => 'pendente', 'desde' => 1.minute.ago.iso8601)).to eq(status: 'pendente', total: 1)
    end

    it 'pendente há mais que a validade: indisponível' do
      expect(prova_com('status' => 'pendente', 'desde' => 4.minutes.ago.iso8601)).to eq(status: 'indisponivel', total: 1)
    end

    it 'de outro ajuste: sem prova' do
      expect(prova_com('status' => 'pendente', 'versao_id' => -1)).to be_nil
    end

    it 'com o ajuste desfeito sozinho pelo código: sem prova' do
      conferencia['desfeito'] = { 'ok' => true }

      expect(prova_com('status' => 'pendente')).to be_nil
    end

    it 'pronta: o ok de cada pergunta (true, false ou nil quando não toca a mudança), sem o veredito cru' do
      perguntas = %w[ok nao nao_testa].map { |nota| { 'pergunta' => nota, 'resposta' => 'r', 'equipe' => false, 'veredito' => nota } }
      saida = prova_com('status' => 'pronta', 'ok' => 1, 'total' => 2, 'perguntas' => perguntas)

      expect(saida[:perguntas].pluck(:ok)).to eq([true, false, nil])
      expect(saida[:perguntas].first.keys).to eq(%i[pergunta resposta equipe ok])
    end

    it 'sem a chave: nil' do
      expect(resultado(conferencia)[:prova]).to be_nil
    end

    # Revisão do t6d (MÉDIO): o ✓ só sai quando cada pedido teve uma pergunta que o testou.
    it 'pronta: diz se a prova cobriu cada pedido (a prova gravada antes da regra conta como completa)' do
      perguntas = [{ 'pergunta' => 'Oi?', 'resposta' => 'r', 'equipe' => false, 'veredito' => 'ok', 'pedido' => 0 }]

      expect(prova_com('status' => 'pronta', 'ok' => 1, 'total' => 1, 'completa' => false, 'perguntas' => perguntas))
        .to include(completa: false)
      expect(prova_com('status' => 'pronta', 'ok' => 1, 'total' => 1, 'perguntas' => perguntas)).to include(completa: true)
    end

    # Cartão da prova incompleta (texto aprovado pelo Rodrigo, 22/10): a tela diz quais pedidos não deu para ver. Só os
    # textos dos pedidos que a prova numerou (os aplicados, na ordem do cartão), nunca o state cru nem a instrução.
    it 'pronta e incompleta: os textos dos pedidos sem teste, na ordem do cartão; completa ou sem testes gravados, sem a lista' do
      conferencia['itens'] = [item('tone', 'mais curto', 'Respostas curtas.'), item('greeting', 'saudação nova', 'Oi.', atendido: false),
                              item('handoff_rule', 'preço com a equipe.', 'Preço vai à equipe.'), item('guardrails', 'sem gíria', 'Sem gíria.')]
      perguntas = [{ 'pergunta' => 'Oi?', 'resposta' => 'r', 'equipe' => false, 'veredito' => 'ok',
                     'testes' => [{ 'pedido' => 0, 'veredito' => 'ok' }] }]
      dados = { 'status' => 'pronta', 'ok' => 1, 'total' => 1, 'perguntas' => perguntas }

      expect(prova_com(dados.merge('completa' => false))).to include(pedidos_sem_teste: ['preço com a equipe', 'sem gíria'])
      expect(prova_com(dados.merge('completa' => true))).not_to have_key(:pedidos_sem_teste)
      sem_testes = perguntas.map { |pergunta| pergunta.except('testes') }
      expect(prova_com(dados.merge('completa' => false, 'perguntas' => sem_testes))).not_to have_key(:pedidos_sem_teste)
    end

    # Cartão (aprovado pelo Rodrigo, 22/10): o ✓ de "mudei" não pode vir junto de "não deu para ver". Cada linha aplicada
    # diz o que a prova viu dela, e a contagem do título é em mudanças (pedidos), não em perguntas.
    describe 'o que a prova viu de cada mudança' do
      before do
        conferencia['itens'] = [item('tone', 'mais curto', 'Respostas curtas.'), item('greeting', 'saudação nova', 'Oi.', atendido: false),
                                item('handoff_rule', 'preço com a equipe', 'Preço vai à equipe.'), item('guardrails', 'sem gíria', 'Sem gíria.')]
      end

      let(:perguntas) do
        [{ 'pergunta' => 'Oi?', 'resposta' => 'r', 'equipe' => false, 'veredito' => 'ok', 'testes' => [{ 'pedido' => 0, 'veredito' => 'ok' }] },
         { 'pergunta' => 'Preço?', 'resposta' => 'r', 'equipe' => false, 'veredito' => 'nao',
           'testes' => [{ 'pedido' => 1, 'veredito' => 'nao' }, { 'pedido' => 0, 'veredito' => 'ok' }] }]
      end

      def com_testes(dados, extra = {})
        resultado(conferencia, { 'prova' => { 'versao_id' => ultimo['versao_id'], 'status' => 'pronta', 'ok' => 1, 'total' => 2,
                                              'completa' => false, 'perguntas' => perguntas }.merge(dados) }.merge(extra))
      end

      it 'cada linha aplicada: ok, nao ou sem_teste; a contagem em mudanças' do
        saida = com_testes({})

        expect(saida[:itens].map { |linha| linha[:prova] }).to eq(['ok', nil, 'nao', 'sem_teste'])
        expect(saida[:prova]).to include(mudancas: { testadas: 2, total: 3, contraditas: 1 })
      end

      it 'prova antiga, sem testes gravados, ou ainda pendente: sem marca nas linhas e sem a contagem' do
        sem_testes = com_testes('perguntas' => perguntas.map { |pergunta| pergunta.except('testes') })
        pendente = com_testes('status' => 'pendente', 'desde' => Time.current.iso8601)

        [sem_testes, pendente].each do |saida|
          expect(saida[:itens]).to all(satisfy { |linha| !linha.key?(:prova) })
          expect(saida[:prova]).not_to have_key(:mudancas)
        end
      end

      it 'cartão de outra conferência que não a da prova: sem marca nas linhas' do
        outra = { 'itens' => [item('tone', 'mais curto', 'Respostas curtas.')] }
        saida = com_testes({}, 'ultimo_ajuste' => ultimo.merge('conferencia' => outra))

        expect(saida[:itens]).to all(satisfy { |linha| !linha.key?(:prova) })
      end
    end

    # A troca para `testes` (revisão do t6d) não mexe na prova já gravada: a tela lê só a `completa` gravada e a
    # pergunta, a resposta e o `veredito` gravado de cada item. Sem campo, com `pedido` ou com `pedidos`, igual a antes.
    it 'prova gravada antes da troca (sem campo, com pedido ou com pedidos) continua igual' do
      sem_campo = [{ 'pergunta' => 'Oi?', 'resposta' => 'r', 'equipe' => false, 'veredito' => 'ok' }]
      antigo = [sem_campo.first.merge('pedido' => 0)]
      da_branch = [sem_campo.first.merge('pedidos' => [0, 1])]
      igual = { status: 'pronta', total: 1, ok: 1, completa: true, perguntas: [{ pergunta: 'Oi?', resposta: 'r', equipe: false, ok: true }] }

      expect(prova_com('status' => 'pronta', 'ok' => 1, 'total' => 1, 'perguntas' => sem_campo)).to eq(igual)
      expect(prova_com('status' => 'pronta', 'ok' => 1, 'total' => 1, 'perguntas' => antigo)).to eq(igual)
      expect(prova_com('status' => 'pronta', 'ok' => 1, 'total' => 1, 'completa' => true, 'perguntas' => da_branch)).to eq(igual)
      expect(prova_com('status' => 'pronta', 'ok' => 1, 'total' => 1, 'completa' => false, 'perguntas' => antigo))
        .to eq(igual.merge(completa: false))
    end
  end
end
