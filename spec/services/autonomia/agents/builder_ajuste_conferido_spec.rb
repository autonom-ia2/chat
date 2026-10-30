require 'rails_helper'

# #1428 (tema 6, parte 2) — a conferência do ajuste no piloto e a UMA correção: o que vai à conferência, o que volta
# ao dono (só texto do código e do Construtor, nunca da conferência), as versões, o teto de tempo, a retomada do mesmo
# token e os desfechos da correção.
RSpec.describe Autonomia::Agents::Builder do
  include_context 'with ajuste por lista'

  describe 'com tudo atendido na conferência' do
    let(:mudancas) { [mudanca('tone', fala, 'Respostas curtas.'), mudanca('instruction', fala, 'No máximo 2 frases.')] }

    before do
      respostas << saida('tone' => 'cordial e curto', 'instruction' => 'Responda em no máximo 2 frases.',
                         'mudancas' => mudancas)
    end

    it 'chama a conferência com a fala, a lista e o agente antes e depois' do
      run_turn

      expect(Autonomia::Agents::ConferenciaDoAjuste).to have_received(:new).with(account: account, credential: anything).once
      expect(recebidas.sole).to include(
        pedido: fala, mudancas: mudancas,
        antes: hash_including('tone' => 'cordial', 'instruction' => 'Atenda o cliente da corretora com cordialidade.',
                              'greeting' => 'Oi! Aqui é o Hubber.', 'voice' => 'masculina'),
        depois: hash_including('tone' => 'cordial e curto', 'instruction' => 'Responda em no máximo 2 frases.')
      )
    end

    it 'guarda o resultado no state e na versão builder_adjust, e fecha sem pergunta' do
      run_turn

      esperado = conferencia_de(mudancas).merge('correcao' => false)
      expect(estado).to include('needs_more_info' => false, 'applied' => true, 'so_pergunta' => false,
                                'conferencia' => esperado, 'pergunta_pendente' => '', 'ajuste_em_curso' => nil,
                                'aplicado_em_token' => thread.build_token)
      versao = versoes_do_construtor.sole
      expect(versao.metadata).to include('pedido' => fala, 'mudancas' => mudancas, 'conferencia' => conferencia_de(mudancas))
      expect(versao.metadata['agente']).to include('tone' => 'cordial e curto')
      expect(calls.size).to eq(1)
    end

    it 'loga quantas conferências houve e quanto duraram, sem conteúdo' do
      allow(Rails.logger).to receive(:info)

      run_turn

      expect(Rails.logger).to have_received(:info).with(a_string_including('[autonomia][builder] ajuste', 'conferencias=1',
                                                                           'conferencias_ms=5', 'desfecho=-'))
      expect(Rails.logger).not_to have_received(:info).with(a_string_including(fala))
    end
  end

  describe 'quando a conferência acha item não atendido' do
    let(:preco) { 'preço passa para a equipe' }
    let(:fala) { "Responda em no máximo 2 frases e #{preco}" }
    let(:primeira) { [mudanca('tone', 'no máximo 2 frases', 'Curto.'), mudanca('handoff_rule', preco, 'Preço vai à equipe.')] }

    before do
      respostas << saida('tone' => 'cordial e curto', 'mudancas' => primeira)
      conferencias << { nao: [1] }
    end

    def correcao_aplicada
      respostas << saida('handoff_rule' => 'Passe para a equipe quando perguntarem preço.',
                         'mudancas' => [mudanca('handoff_rule', preco, 'Preço vai à equipe.')])
    end

    it 'faz UMA correção: o que faltou vai como dado num item user, e no developer só o aviso fixo' do
      correcao_aplicada

      run_turn

      expect(calls.size).to eq(2)
      dado, aviso = calls.last[:input].last(2)
      expect(dado).to include(role: 'user')
      expect(dado[:content].first[:text]).to include('E DADO', "- #{preco} (campo handoff_rule)")
      expect(dado[:content].first[:text].split('TEXTOS DE PEDIDO DA LISTA').first).not_to include('no máximo 2 frases')
      expect(aviso).to eq(role: 'developer', content: [{ type: 'input_text', text: described_class::CorrecaoDoAjuste::AVISO }])
      expect(calls.last[:timeout]).to eq(described_class::FechamentoDoAjuste::TIMEOUT_DA_CORRECAO_S)
      expect(calls.last[:input]).to include(hash_including(content: [hash_including(text: a_string_including('tone: cordial e curto'))]))
    end

    # Forense do t6d (P3): a correção não pode trocar o texto do pedido (composto x partes): o cartão duplicaria a linha.
    # Revisão do t6d (MÉDIO 1): o schema da correção é o mesmo da primeira chamada (cache); quem confere o pedido é o
    # código. O ponto final a mais volta ao texto da lista, e o cartão fica com uma linha por pedido.
    it 'a correção usa o mesmo schema; o pedido com ponto a mais volta ao texto da lista e o cartão não duplica' do
      respostas << saida('handoff_rule' => 'Passe para a equipe quando perguntarem preço.',
                         'mudancas' => [mudanca('handoff_rule', "#{preco}.", 'Preço vai à equipe.')])

      run_turn

      expect(calls.last[:schema]).to equal(calls.first[:schema])
      expect(recebidas.last[:mudancas].pluck('pedido')).to eq(['no máximo 2 frases', preco, preco])
      linhas = Autonomia::Agents::ResultadoDoAjuste.new(thread.reload, estado['conferencia']).linhas
      expect(linhas.size).to eq(2)
    end

    # Nunca some em silêncio: o item de pedido fora da lista sai com log e a conferência registra quantos saíram.
    it 'o item da correção com outro texto de pedido não é gravado, e a conferência conta o descarte' do
      allow(Rails.logger).to receive(:warn)
      respostas << saida('handoff_rule' => 'Passe para a equipe quando perguntarem preço.',
                         'mudancas' => [mudanca('handoff_rule', 'valores com a equipe', 'Preço vai à equipe.')])

      run_turn

      expect(agent.reload.handoff_rule).to eq('Passe para a equipe quando o cliente pedir.')
      expect(estado['conferencia']).to include('itens_descartados' => 1)
      expect(Rails.logger).to have_received(:warn).with(a_string_including('pedido_fora_da_lista'))
    end

    it 'com a correção atendida: fecha sem pergunta, e só uma versão fica na lista' do
      correcao_aplicada

      run_turn

      expect(agent.reload).to have_attributes(tone: 'cordial e curto', handoff_rule: 'Passe para a equipe quando perguntarem preço.')
      expect(estado).to include('needs_more_info' => false, 'applied' => true)
      expect(estado['conferencia']).to include('correcao' => true, 'falta' => false)
      expect(recebidas.last[:mudancas].size).to eq(3)
      primeira_versao, correcao = versoes_do_construtor.to_a
      expect(primeira_versao.metadata).to include('fora_da_lista' => true, 'corrigida_por' => correcao.id)
      expect(correcao.metadata).to include('correcao_de' => primeira_versao.id)
      expect(agent.instruction_versions.na_lista.where(reason: 'builder_adjust')).to eq([correcao])
    end

    # #1850: o cartão ⚠ já mostra "Não consegui aplicar: preço passa para a equipe". Na tela, enquanto o cartão está lá,
    # a bolha só pergunta (`pergunta_curta` do cartão); a conversa e a pendência guardam a pergunta inteira, com o pedido.
    it 'se ainda faltar, guarda a pergunta inteira e o cartão ⚠ leva a versão que só pergunta' do
      correcao_aplicada
      conferencias << { nao: [2] }

      run_turn

      pergunta = "#{texto(:nao_consegui, pedidos: preco)} #{texto(:de_outro_jeito)}"
      expect(agent.reload.tone).to eq('cordial e curto')
      expect(estado).to include('needs_more_info' => true, 'applied' => true, 'next_question' => pergunta,
                                'pergunta_pendente' => pergunta)
      expect(thread.messages.last).to include('role' => 'assistant', 'content' => pergunta)
      cartao = Autonomia::Agents::ResultadoDoAjuste.new(thread.reload).to_h
      expect(cartao[:itens]).to include({ estado: 'nao_aplicado', texto: preco })
      expect(cartao[:pergunta_curta]).to eq(texto(:de_outro_jeito))
    end

    # Revisão do #1850 (ALTO): o turno seguinte recebe a pendência com o pedido, e a versão curta sai da tela.
    it 'no turno seguinte, o Construtor recebe a pendência com o pedido e o cartão não leva mais a versão curta' do
      correcao_aplicada
      conferencias << { nao: [2] }
      run_turn
      thread.append_message!('user', 'A equipe comercial')
      respostas << saida('needs_more_info' => true, 'next_question' => 'Qual o telefone da equipe?')

      run_turn

      contexto = calls.last[:input].map { |item| item[:content].to_a.pluck(:text).join }.join("\n")
      expect(contexto).to include('PERGUNTA PENDENTE', texto(:nao_consegui, pedidos: preco))
      expect(thread.messages.pluck('content')).to include("#{texto(:nao_consegui, pedidos: preco)} #{texto(:de_outro_jeito)}")
      expect(Autonomia::Agents::ResultadoDoAjuste.new(thread.reload).to_h).not_to have_key(:pergunta_curta)
      expect(estado).to include('applied' => false, 'pergunta_na_tela' => nil)
    end

    it 'depois do Desfazer, o cartão não leva a versão curta (a conversa mostra a pergunta inteira)' do
      correcao_aplicada
      conferencias << { nao: [2] }
      run_turn

      thread.reload.update!(state: thread.state.deep_merge('ultimo_ajuste' => { 'desfeito' => true }))

      expect(Autonomia::Agents::ResultadoDoAjuste.new(thread.reload).to_h).not_to have_key(:pergunta_curta)
      expect(thread.messages.last['content']).to start_with(texto(:nao_consegui, pedidos: preco))
    end

    it 'se a correção não aplicar e explicar, a explicação dela vai na pergunta' do
      respostas << saida('needs_more_info' => true, 'next_question' => 'Qual equipe?')

      run_turn

      expect(conferente).to have_received(:conferir).once
      expect(estado).to include('needs_more_info' => true, 'applied' => true,
                                'next_question' => "#{texto(:nao_consegui, pedidos: preco)} Qual equipe?")
      expect(estado['conferencia']).to include('correcao' => false)
      expect(Autonomia::Agents::ResultadoDoAjuste.new(thread.reload).to_h[:pergunta_curta]).to eq('Qual equipe?')
    end

    it 'se a correção mudar nada, não conta como aplicada nem esconde a primeira versão' do
      respostas << saida('mudancas' => [mudanca('handoff_rule', preco)])

      run_turn

      expect(conferente).to have_received(:conferir).once
      expect(estado['next_question']).to start_with(texto(:nao_consegui, pedidos: preco))
      expect(agent.instruction_versions.na_lista.where(reason: 'builder_adjust').count).to eq(1)
    end

    it 'chamada da correção falha: o que entrou fica aplicado e o turno não vira falha' do
      respostas << :falha

      run_turn

      expect(agent.reload.tone).to eq('cordial e curto')
      expect(thread.reload).to be_ready
      expect(estado).to include('needs_more_info' => true, 'applied' => true)
    end

    # A segunda aplicação (a da correção) falha; a primeira já venceu.
    def falhar_na_correcao(erro)
      vezes = 0
      allow(builder).to receive(:aplicar_lista).and_wrap_original do |original, *args, **kwargs|
        vezes += 1
        raise erro if vezes == 2

        original.call(*args, **kwargs)
      end
    end

    it 'erro de banco na correção não vira falha' do
      correcao_aplicada
      falhar_na_correcao(ActiveRecord::StatementInvalid.new('falhou'))

      run_turn

      expect(estado).to include('needs_more_info' => true, 'applied' => true)
    end

    it 'agente que virou manual durante a correção: fecha sem pergunta ao dono' do
      correcao_aplicada
      falhar_na_correcao(Autonomia::Agents::Agent::ModoManual)

      run_turn

      expect(estado).to include('needs_more_info' => true, 'applied' => true, 'pergunta_pendente' => '')
    end

    it 'correção derrotada por um ajuste mais novo: avisa, não diz "não consegui aplicar"' do
      correcao_aplicada
      vezes = 0
      allow(builder).to receive(:aplicar_lista).and_wrap_original do |original, *args, **kwargs|
        vezes += 1
        Autonomia::Agents::BuildThread.create!(account: account, agent: agent) if vezes == 2
        original.call(*args, **kwargs)
      end

      run_turn

      expect(estado).to include('needs_more_info' => true, 'applied' => true, 'next_question' => texto(:correcao_superada),
                                'pergunta_pendente' => '')
    end

    it 'o agente mudou por outro caminho depois da primeira escrita: não corrige e avisa' do
      allow(conferente).to receive(:conferir) do |**kwargs|
        Autonomia::Agents::Agent.where(id: agent.id).update_all(updated_at: 1.minute.from_now) # rubocop:disable Rails/SkipsModelValidations
        conferencia_de(kwargs[:mudancas], nao: [1])
      end

      run_turn

      expect(calls.size).to eq(1)
      expect(estado).to include('needs_more_info' => true, 'applied' => true, 'next_question' => texto(:agente_mudou),
                                'pergunta_pendente' => '')
    end

    it 'passado o teto de tempo do turno, não corrige: o que faltou vira pergunta' do
      correcao_aplicada
      allow(conferente).to receive(:conferir) do |**kwargs|
        travel(201.seconds)
        conferencia_de(kwargs[:mudancas], nao: [1])
      end

      run_turn

      expect(calls.size).to eq(1)
      expect(estado['next_question']).to start_with(texto(:nao_consegui, pedidos: preco))
    end
  end

  # B da revisão (e prova A): conflito sem falta vira pergunta, sem correção.
  describe 'quando só há conflito, com tudo atendido' do
    before do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone', 'curto')])
      conferencias << { conflito: true }
    end

    it 'pergunta ao dono sem correção e sem "não consegui aplicar"' do
      run_turn

      expect(calls.size).to eq(1)
      expect(agent.reload.tone).to eq('curto')
      expect(estado).to include('needs_more_info' => true, 'applied' => true,
                                'next_question' => texto(:conflito, pedidos: 'curto'))
    end
  end

  describe 'quando faltou um pedido da fala que não entrou na lista' do
    before do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone', 'curto')])
      conferencias << { fora: true } << { fora: true }
    end

    it 'corrige uma vez e, se ainda faltar, pergunta sem citar texto da conferência' do
      respostas << saida('greeting' => 'Olá!', 'mudancas' => [mudanca('greeting', 'saudação')])

      run_turn

      expect(calls.last[:input].last(2).first[:content].first[:text]).to include('nao entrou na lista')
      expect(estado['next_question']).to eq("#{texto(:nao_consegui_tudo)} #{texto(:de_outro_jeito)}")
      cartao = Autonomia::Agents::ResultadoDoAjuste.new(thread.reload).to_h
      expect(cartao).to include(faltou_fora: true, pergunta_curta: texto(:de_outro_jeito))
    end
  end

  describe 'quando a fala responde a uma pergunta do Construtor' do
    let(:fala) { 'sim' }

    before do
      thread.update!(messages: [{ 'role' => 'user', 'content' => 'Deixe as respostas curtas' },
                                { 'role' => 'assistant', 'content' => 'No máximo 2 frases?' },
                                { 'role' => 'user', 'content' => 'sim' }])
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone', 'no máximo 2 frases')])
    end

    it 'a conferência lê a pergunta anterior junto, e a versão guarda só a fala do dono' do
      run_turn

      expect(recebidas.sole[:pedido]).to eq("Mensagem anterior do Construtor: No máximo 2 frases?\nResposta do dono: sim")
      expect(versoes_do_construtor.sole.metadata['pedido']).to eq('sim')
    end
  end

  describe 'quando o turno só tem imagem' do
    before do
      thread.update!(messages: [{ 'role' => 'user', 'content' => 'Mude o tom' },
                                { 'role' => 'assistant', 'content' => 'Qual tom?' },
                                { 'role' => 'user', 'content' => '' }])
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone', 'como na imagem')])
    end

    it 'a conferência usa a última mensagem do dono, mesmo vazia, com a pergunta anterior' do
      run_turn

      expect(recebidas.sole[:pedido]).to eq("Mensagem anterior do Construtor: Qual tom?\nResposta do dono: " \
                                            '(o dono mandou so imagem, sem texto)')
    end
  end

  describe 'quando a conferência está indisponível' do
    before do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone')])
      conferencias << { erro: true }
    end

    it 'o que entrou fica aplicado, sem correção, e o state registra a falta da conferência' do
      run_turn

      expect(calls.size).to eq(1)
      expect(agent.reload.tone).to eq('curto')
      expect(estado).to include('needs_more_info' => false, 'applied' => true)
      expect(estado['conferencia']).to include('erro' => 'conferencia_indisponivel')
    end
  end

  # F da revisão: o re-run do mesmo token (o job caiu depois da primeira escrita) não chama o Construtor de novo.
  describe 'quando o turno é retomado com o mesmo token' do
    before do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone')])
      conferencias << RuntimeError.new('o job caiu')
    end

    it 'pula o Construtor, confere e fecha uma vez' do
      token = thread.begin_build!
      expect { builder.run!(token) }.to raise_error(RuntimeError)
      expect(estado).to include('aplicado_em_token' => token)
      expect(estado['ajuste_em_curso']).to include('token' => token, 'mudancas' => [mudanca('tone')])

      described_class.new(account: account, build_thread: thread.reload).tap do |retomada|
        allow(retomada).to receive_messages(credential: { api_key: 'k' }, client: fake_client)
        retomada.run!(token)
      end

      expect(calls.size).to eq(1)
      expect(versoes_do_construtor.count).to eq(1)
      expect(estado).to include('applied' => true, 'needs_more_info' => false, 'ajuste_em_curso' => nil)
    end

    it 'a primeira escrita toca o updated_at da thread' do
      token = nil
      travel_to(1.minute.ago) { token = thread.begin_build! }
      expect { builder.run!(token) }.to raise_error(RuntimeError)

      expect(thread.reload.updated_at).to be > 30.seconds.ago
    end
  end

  # I da revisão: a credencial é resolvida uma vez no turno, mesmo com conferência e correção.
  describe 'a credencial do turno' do
    let(:builder_real) { described_class.new(account: account, build_thread: thread) }

    it 'é resolvida uma vez' do
      resolvedor = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' })
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolvedor)
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(fake_client)
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone')])
      respostas << saida('greeting' => 'Olá', 'mudancas' => [mudanca('greeting')])
      conferencias << { nao: [0] }

      builder_real.run!(thread.begin_build!)

      expect(calls.size).to eq(2)
      expect(resolvedor).to have_received(:resolve).once
    end
  end

  # Revisão da parte 2 (ALTO dos dois revisores): o que o dono não pediu. Os itens se agrupam pelo `pedido` que o
  # Construtor escreveu; o código só desfaz sozinho quando TODOS estão sem pedido.
  describe 'quando a conferência aponta mudança sem pedido do dono' do
    def sem_pedido(*indices, mudou_antes: false)
      allow(conferente).to receive(:conferir) do |**kwargs|
        recebidas << kwargs
        Autonomia::Agents::Agent.where(id: agent.id).update_all(updated_at: 1.minute.from_now) if mudou_antes # rubocop:disable Rails/SkipsModelValidations
        conferencia_de(kwargs[:mudancas]).then do |conf|
          conf.merge('itens' => conf['itens'].each_with_index.map { |item, i| item.merge('pedido_pelo_dono' => indices.exclude?(i)) })
        end
      end
    end

    it 'tudo sem pedido (prova B2): desfaz, não fecha como aplicado, diz o que desfez e a versão sai da lista' do
      respostas << saida('human_card' => 'O Hubber atende clientes da corretora.',
                         'mudancas' => [mudanca('human_card', 'explica', 'Reescrevi o cartão.')])
      sem_pedido(0)

      run_turn

      expect(agent.reload.human_card).to eq('O Hubber atende os clientes.')
      expect(estado).to include('applied' => false, 'needs_more_info' => true,
                                'next_question' => texto(:desfiz_nao_pedido, resumos: 'Reescrevi o cartão'))
      expect(estado.dig('conferencia', 'desfeito')).to eq('campos' => ['human_card'], 'ok' => true)
      expect(agent.instruction_versions.na_lista.where(reason: 'builder_adjust')).to be_empty
      expect(versoes_do_construtor.sole.metadata).to include('fora_da_lista' => true, 'desfeita' => true)
    end

    it 'um pedido com dois destinos: o destino que a conferência marcou sem pedido NÃO é desfeito' do
      respostas << saida('tone' => 'curto', 'instruction' => 'Responda em no máximo 2 frases.',
                         'mudancas' => [mudanca('tone', fala, 'Respostas curtas.'), mudanca('instruction', fala, 'No máximo 2 frases.')])
      sem_pedido(1)

      run_turn

      expect(agent.reload).to have_attributes(tone: 'curto', instruction: 'Responda em no máximo 2 frases.')
      expect(estado).to include('applied' => true, 'needs_more_info' => false, 'pergunta_pendente' => '')
      expect(estado['conferencia'].keys).not_to include('desfeito', 'sem_pedido')
    end

    # Rodada 6: sem oferta de desfazer pela conversa. Parte 3: o dono é informado pelo cartão da tela (linha sem_pedido),
    # sem bolha "também mudei" na conversa; o desfazer exato é o botão Desfazer.
    it 'parte sem pedido: tudo fica aplicado, o cartão informa e a conversa não ganha bolha, sem pergunta nem pendência' do
      respostas << saida('tone' => 'curto', 'greeting' => 'Olá!',
                         'mudancas' => [mudanca('tone', fala, 'Respostas curtas.'), mudanca('greeting', 'x', 'Saudação nova.')])
      sem_pedido(1)

      run_turn

      expect(agent.reload).to have_attributes(tone: 'curto', greeting: 'Olá!')
      expect(estado).to include('applied' => true, 'needs_more_info' => false, 'next_question' => '',
                                'pergunta_pendente' => '', 'parcial' => false)
      expect(estado['conferencia']['sem_pedido'].pluck('resumo')).to eq(['Saudação nova.'])
      expect([estado.key?('desfazer_pendente'), thread.messages.pluck('role')]).to eq([false, ['user']])
      expect(agent.instruction_versions.na_lista.where(reason: 'builder_adjust').count).to eq(1)
      referencia = estado['nao_pedido_anterior']
      expect(referencia).to include('campos' => ['greeting'])
      expect(agent.instruction_versions.find(referencia['versao_antes_id']).metadata.dig('agente', 'greeting'))
        .to eq('Oi! Aqui é o Hubber.')
    end

    # Rodada 7 (adversarial P2): só se cita o que mudou de fato.
    it 'campo não pedido que o Construtor devolveu igual: nenhum aviso' do
      lista = [mudanca('tone', fala, 'Respostas curtas.'), mudanca('greeting', 'x', 'Saudação nova.')]
      respostas << saida('tone' => 'curto', 'mudancas' => lista)
      sem_pedido(1)

      run_turn

      expect(estado).to include('applied' => true, 'needs_more_info' => false, 'nao_pedido_anterior' => nil)
      expect(estado['conferencia'].keys).not_to include('sem_pedido')
      expect(thread.messages.pluck('role')).to eq(['user'])
    end

    def turno_seguinte(fala_do_dono, saida_do_modelo)
      thread.append_message!('user', fala_do_dono)
      respostas << saida_do_modelo
      described_class.new(account: account, build_thread: thread.reload).tap do |outro|
        allow(outro).to receive_messages(credential: { api_key: 'k' }, client: fake_client, cliente_da_correcao: fake_client)
        outro.run!(thread.begin_build!)
      end
    end

    # Revisão crítica do 66d97ac642 (BAIXO): a instrução sem pedido volta com o andaime e o cartão de antes.
    it 'instrução não pedida: o turno seguinte recebe a instrução, o andaime e o cartão de antes' do
      respostas << saida('greeting' => 'Olá!', 'instruction' => 'Outra instrução.', 'scaffold' => 'outro andaime',
                         'human_card' => 'Outro cartão.',
                         'mudancas' => [mudanca('greeting', 'saudação Olá'), mudanca('instruction', 'x', 'Instrução nova.')])
      sem_pedido(1)
      run_turn
      allow(conferente).to receive(:conferir) { |**kwargs| conferencia_de(kwargs[:mudancas]) }

      leitor = described_class.new(account: account, build_thread: thread.reload)
      allow(leitor).to receive(:credential).and_return(api_key: 'k')
      leitor.send(:preparar_ajuste!, 'outro-token')
      a_conferencia_le = leitor.send(:valores_antes_do_nao_pedido)
      turno_seguinte('Tira o que você mudou na instrução', saida('so_pergunta' => true, 'next_question' => 'Ok.'))

      contexto = calls.last[:input].map { |item| item[:content].first[:text] }.find { |texto| texto.include?('antes do ultimo ajuste') }
      expect(contexto).to include('instruction: Atenda o cliente da corretora com cordialidade.', 'scaffold: andaime',
                                  'human_card: O Hubber atende os clientes.')
      # À conferência o andaime não vai.
      expect(a_conferencia_le).to include('instruction: Atenda', 'human_card: O Hubber')
      expect(a_conferencia_le).not_to include('scaffold')
    end

    # Parte 3 (crítico Q3): o "tira isso" e o aviso do não pedido sobrevivem a uma pergunta; duram até o próximo ajuste
    # aplicado ou o Desfazer.
    it 'depois de uma pergunta, a faixa mostra o não pedido e o "tira isso" ainda recebe o valor de antes' do
      respostas << saida('tone' => 'curto', 'greeting' => 'Olá!',
                         'mudancas' => [mudanca('tone', fala, 'Respostas curtas.'), mudanca('greeting', 'x', 'Saudação nova.')])
      sem_pedido(1)
      run_turn

      turno_seguinte('O que você faz hoje?', saida('so_pergunta' => true, 'next_question' => 'Hoje eu atendo.'))

      expect(estado).to include('applied' => false, 'nao_pedido_anterior' => hash_including('campos' => ['greeting']))
      expect(Autonomia::Agents::ResultadoDoAjuste.ultima_mudanca_desfazivel(agent.reload))
        .to include(thread_id: thread.id, linhas: ['Respostas curtas'], sem_pedido: ['Saudação nova'])

      tira = saida('greeting' => 'Oi! Aqui é o Hubber.', 'mudancas' => [mudanca('greeting', 'tira a saudação nova')])
      turno_seguinte('Tira a saudação nova', tira)

      contexto = calls.last[:input].map { |item| item[:content].first[:text] }.find { |texto| texto.include?('antes do ultimo ajuste') }
      expect(contexto).to include('greeting: Oi! Aqui é o Hubber.')
    end

    # Parte 3 (crítico 3): o contexto do "tira isso" só vai enquanto o Desfazer ainda vale.
    def contexto_do_tira_isso_depois
      respostas << saida('tone' => 'curto', 'greeting' => 'Olá!',
                         'mudancas' => [mudanca('tone', fala, 'Respostas curtas.'), mudanca('greeting', 'x', 'Saudação nova.')])
      sem_pedido(1)
      run_turn
      yield
      turno_seguinte('Tira a saudação nova', saida('so_pergunta' => true, 'next_question' => 'Ok.'))
      calls.last[:input].map { |item| item[:content].first[:text] }.find { |texto| texto.include?('antes do ultimo ajuste') }
    end

    it 'V1: depois de uma volta por Versões, o "tira isso" sai do state e não vai ao Construtor' do
      contexto = contexto_do_tira_isso_depois do
        agent.reload.restore_instruction!(agent.instruction_versions.find_by!(reason: 'base'))
        expect(estado.keys).not_to include('nao_pedido_anterior', 'ultimo_ajuste')
      end

      expect(contexto).to be_nil
    end

    it 'V2: depois de uma mudança pela gaveta, o "tira isso" não vai ao Construtor' do
      contexto = contexto_do_tira_isso_depois { agent.reload.update!(handoff_rule: 'Mudado pela gaveta.') }

      expect(contexto).to be_nil
    end

    # Rodada 7 (crítico MÉDIO): o "é só me dizer o que tirar" funciona: o turno seguinte recebe o valor de antes.
    it 'o turno seguinte recebe o valor de antes do campo não pedido, e a chave sai depois' do
      respostas << saida('tone' => 'curto', 'greeting' => 'Olá!',
                         'mudancas' => [mudanca('tone', fala, 'Respostas curtas.'), mudanca('greeting', 'x', 'Saudação nova.')])
      sem_pedido(1)
      run_turn
      expect(estado['nao_pedido_anterior'].to_json).not_to include('Oi! Aqui')
      allow(conferente).to receive(:conferir) do |**kwargs|
        recebidas << kwargs
        conferencia_de(kwargs[:mudancas])
      end

      thread.append_message!('user', 'Tira a saudação nova')
      respostas << saida('greeting' => 'Oi! Aqui é o Hubber.', 'mudancas' => [mudanca('greeting', 'tira a saudação nova')])
      described_class.new(account: account, build_thread: thread.reload).tap do |outro|
        allow(outro).to receive_messages(credential: { api_key: 'k' }, client: fake_client, cliente_da_correcao: fake_client)
        outro.run!(thread.begin_build!)
      end

      contexto = calls.last[:input].map { |item| item[:content].first[:text] }.find { |texto| texto.include?('antes do ultimo ajuste') }
      expect(contexto).to include('greeting: Oi! Aqui é o Hubber.')
      # Eval de 17/10: a conferência também precisa do valor de antes, senão julga "como era" sem saber o que era.
      expect(recebidas.last[:valores_antes]).to include('greeting: Oi! Aqui é o Hubber.')
      # Rodada 9 (obrigatória): o valor de antes nunca vai dentro da fala do dono.
      expect(recebidas.last[:pedido]).to include('Tira a saudação nova')
      expect(recebidas.last[:pedido]).not_to include('Oi! Aqui é o Hubber.')
      expect(agent.reload.greeting).to eq('Oi! Aqui é o Hubber.')
      expect(estado['nao_pedido_anterior']).to be_nil
    end

    # Rodada 5 (MÉDIO): o destino secundário pela tabela é protegido mesmo com o `pedido` escrito diferente.
    it 'a instrução que acompanha o tom pela tabela não conta como sem pedido, mesmo com outro texto de pedido' do
      respostas << saida('tone' => 'curto', 'instruction' => 'Responda em no máximo 2 frases.',
                         'mudancas' => [mudanca('tone', 'no máximo 2 frases'), mudanca('instruction', 'limitar a duas frases')])
      sem_pedido(1)

      run_turn

      expect(agent.reload).to have_attributes(tone: 'curto', instruction: 'Responda em no máximo 2 frases.')
      expect(estado).to include('needs_more_info' => false, 'pergunta_pendente' => '')
      expect(estado['conferencia'].keys).not_to include('sem_pedido', 'desfeito')
    end

    it 'o agente mudou por outro caminho antes de desfazer: não desfaz e diz o que ficou sem pedido' do
      respostas << saida('greeting' => 'Olá!', 'mudancas' => [mudanca('greeting', 'x', 'Saudação nova.')])
      sem_pedido(0, mudou_antes: true)

      run_turn

      expect(agent.reload.greeting).to eq('Olá!')
      expect(estado).to include('applied' => true, 'needs_more_info' => true,
                                'next_question' => texto(:nao_desfiz, resumos: 'Saudação nova'))
    end

    it 'o token da geração foi tomado antes de desfazer: não desfaz (job antigo)' do
      respostas << saida('greeting' => 'Olá!', 'mudancas' => [mudanca('greeting', 'x', 'Saudação nova.')])
      allow(conferente).to receive(:conferir) do |**kwargs|
        Autonomia::Agents::BuildThread.where(id: thread.id).update_all(build_token: 'outro') # rubocop:disable Rails/SkipsModelValidations
        conf = conferencia_de(kwargs[:mudancas])
        conf.merge('itens' => conf['itens'].map { |item| item.merge('pedido_pelo_dono' => false) })
      end

      run_turn

      expect(agent.reload.greeting).to eq('Olá!')
    end

    # Mutante q9: a versão de antes é a imediatamente anterior à aplicação, não a primeira do agente.
    it 'com versões antigas antes da base, volta ao estado de logo antes do ajuste' do
      agent.update!(greeting: 'Saudação antiga')
      agent.record_instruction_version!(reason: 'manual_edit')
      agent.update!(instruction: 'Instrução do meio.', greeting: 'Oi! Aqui é o Hubber.')
      agent.record_instruction_version!(reason: 'manual_edit')
      respostas << saida('instruction' => 'Instrução do meio.', 'greeting' => 'Olá!',
                         'mudancas' => [mudanca('greeting', 'x', 'Saudação nova.')])
      sem_pedido(0)

      run_turn

      expect(agent.reload).to have_attributes(greeting: 'Oi! Aqui é o Hubber.', instruction: 'Instrução do meio.')
    end
  end

  # Rodada 6 (BAIXO): o desfazer recusa a Lia na primeira linha, como todo escritor da instrução.
  it 'desfazer_do_construtor! recusa a Lia (instrução mantida pela Autonom.ia)' do
    lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', instruction: 'retrato')

    expect do
      lia.desfazer_do_construtor!(versoes: { antes: 0, aplicacao: 0 }, colunas: ['greeting'], chaves: [],
                                  esperado: lia.updated_at.iso8601(6), geracao: { thread_id: thread.id, token: 'x' })
    end.to raise_error(Autonomia::Agents::Agent::InstrucaoMantida)
  end

  # Crítica (2ª rodada, BAIXO): o state não guarda a instrução crua, e a falha limpa o ajuste em curso.
  describe 'o ajuste em curso no state' do
    before do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone')])
      allow(conferente).to receive(:conferir) do |**kwargs|
        recebidas << kwargs.merge(em_curso: thread.reload.state['ajuste_em_curso'])
        conferencia_de(kwargs[:mudancas])
      end
    end

    it 'guarda o id da versão de antes, não a instrução; a conferência lê o antes dessa versão' do
      run_turn

      em_curso = recebidas.sole[:em_curso]
      expect(em_curso.keys).not_to include('antes')
      expect(em_curso.to_json).not_to include('Atenda o cliente da corretora')
      expect(recebidas.sole[:antes]).to include('instruction' => 'Atenda o cliente da corretora com cordialidade.', 'tone' => 'cordial')
    end

    it 'mark_failed! limpa o ajuste em curso e a referência do não pedido' do
      token = thread.begin_build!
      thread.guardar_no_estado!(token, 'ajuste_em_curso' => { 'token' => token }, 'nao_pedido_anterior' => { 'campos' => ['tone'] })

      thread.mark_failed!(token, 'build_error')

      expect(estado.values_at('ajuste_em_curso', 'nao_pedido_anterior')).to eq([nil, nil])
    end
  end

  # Crítica (2ª rodada, BAIXO): tempo. Sem nova tentativa, toque antes da correção e 2ª conferência pulada no teto.
  describe 'o teto de tempo' do
    let(:fala) { 'Responda curto e preço passa para a equipe' }
    let(:correcao_do_preco) { saida('handoff_rule' => 'Preço vai à equipe.', 'mudancas' => [mudanca('handoff_rule', 'preço')]) }

    before do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone'), mudanca('handoff_rule', 'preço')])
      conferencias << { nao: [1] }
    end

    # Mutante q10: o teto conta do ÚLTIMO toque (a primeira escrita), não do começo do turno.
    it 'o teto conta do último toque: turno longo antes da escrita ainda corrige' do
      allow(fake_client).to receive(:create) do |**params|
        calls << params
        travel(150.seconds) if calls.size == 1
        resposta = calls.size == 1 ? respostas.shift : correcao_do_preco
        { text: resposta.to_json, usage: {}, tools_used: [] }
      end
      allow(conferente).to receive(:conferir) do |**kwargs|
        recebidas << kwargs
        travel(100.seconds) if recebidas.size == 1
        conferencia_de(kwargs[:mudancas], nao: recebidas.size == 1 ? [1] : [])
      end

      run_turn

      expect(calls.size).to eq(2)
      expect(agent.reload.handoff_rule).to eq('Preço vai à equipe.')
    end

    it 'a correção não tem nova tentativa' do
      expect(described_class::FechamentoDoAjuste::TENTATIVAS_DA_CORRECAO).to eq(0)
      expect(Autonomia::Agents::ConferenciaDoAjuste::TENTATIVAS).to eq(0)
    end

    it 'toca a thread antes da correção' do
      allow(fake_client).to receive(:create) do |**params|
        calls << params
        resposta = calls.size == 1 ? respostas.shift : correcao_do_preco
        recebidas << { toque: thread.reload.updated_at } if calls.size == 2
        { text: resposta.to_json, usage: {}, tools_used: [] }
      end
      travel(100.seconds) # entre a primeira escrita e a correção

      run_turn

      expect(recebidas.find { |r| r.key?(:toque) }[:toque]).to be > 5.seconds.ago
    end

    it 'passado o teto durante a correção, a 2ª conferência é pulada e o dono é avisado' do
      allow(fake_client).to receive(:create) do |**params|
        calls << params
        travel(201.seconds) if calls.size == 2
        resposta = calls.size == 1 ? respostas.shift : correcao_do_preco
        { text: resposta.to_json, usage: {}, tools_used: [] }
      end

      run_turn

      expect(conferente).to have_received(:conferir).once
      expect(estado).to include('applied' => true, 'needs_more_info' => true, 'next_question' => texto(:nao_conferido, pedidos: 'preço'))
    end
  end

  # Adversarial (2ª rodada): a correção que venceu fica no state; o re-run não a refaz.
  describe 'quando o turno cai depois da correção' do
    before do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone'), mudanca('handoff_rule', 'preço')])
      respostas << saida('handoff_rule' => 'Preço vai à equipe.', 'mudancas' => [mudanca('handoff_rule', 'preço')])
      conferencias << { nao: [1] } << RuntimeError.new('o job caiu')
    end

    it 'o re-run só confere e fecha: sem Construtor, sem agente_mudou falso e com uma versão na lista' do
      token = thread.begin_build!
      expect { builder.run!(token) }.to raise_error(RuntimeError)
      expect(estado.dig('ajuste_em_curso', 'correcao', 'mudancas')).to eq([mudanca('handoff_rule', 'preço')])

      described_class.new(account: account, build_thread: thread.reload).tap do |retomada|
        allow(retomada).to receive_messages(credential: { api_key: 'k' }, client: fake_client, cliente_da_correcao: fake_client)
        retomada.run!(token)
      end

      expect(calls.size).to eq(2)
      expect(estado).to include('applied' => true, 'needs_more_info' => false, 'ajuste_em_curso' => nil)
      expect(estado['conferencia']).to include('correcao' => true)
      expect(agent.instruction_versions.na_lista.where(reason: 'builder_adjust').count).to eq(1)
    end
  end

  # Adversarial (2ª rodada): a volta de versão entre a checagem e a escrita da correção é vista sob a trava.
  it 'o agente muda entre a checagem e a escrita da correção: não escreve e avisa' do
    respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone'), mudanca('handoff_rule', 'preço')])
    respostas << saida('handoff_rule' => 'Preço vai à equipe.', 'mudancas' => [mudanca('handoff_rule', 'preço')])
    conferencias << { nao: [1] }
    vezes = 0
    allow(builder).to receive(:aplicar_lista).and_wrap_original do |original, *args, **kwargs|
      vezes += 1
      Autonomia::Agents::Agent.where(id: agent.id).update_all(updated_at: 1.minute.from_now) if vezes == 2 # rubocop:disable Rails/SkipsModelValidations
      original.call(*args, **kwargs)
    end

    run_turn

    expect(agent.reload.handoff_rule).to eq('Passe para a equipe quando o cliente pedir.')
    expect(estado).to include('needs_more_info' => true, 'next_question' => texto(:agente_mudou))
    expect(versoes_do_construtor.count).to eq(1)
  end
end
