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
      expect(dado[:content].first[:text]).not_to include('no máximo 2 frases')
      expect(aviso).to eq(role: 'developer', content: [{ type: 'input_text', text: described_class::AjustePorLista::AVISO_DE_CORRECAO }])
      expect(calls.last[:timeout]).to eq(described_class::FechamentoDoAjuste::TIMEOUT_DA_CORRECAO_S)
      expect(calls.last[:input]).to include(hash_including(content: [hash_including(text: a_string_including('tone: cordial e curto'))]))
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

    it 'se ainda faltar, vira pergunta montada pelo código com o pedido do Construtor' do
      correcao_aplicada
      conferencias << { nao: [2] }

      run_turn

      pergunta = "#{texto(:nao_consegui, pedidos: preco)} #{texto(:de_outro_jeito)}"
      expect(agent.reload.tone).to eq('cordial e curto')
      expect(estado).to include('needs_more_info' => true, 'applied' => true, 'next_question' => pergunta,
                                'pergunta_pendente' => pergunta)
      expect(thread.messages.last).to include('role' => 'assistant', 'content' => pergunta)
    end

    it 'se a correção não aplicar e explicar, a explicação dela vai na pergunta' do
      respostas << saida('needs_more_info' => true, 'next_question' => 'Qual equipe?')

      run_turn

      expect(conferente).to have_received(:conferir).once
      expect(estado).to include('needs_more_info' => true, 'applied' => true,
                                'next_question' => "#{texto(:nao_consegui, pedidos: preco)} Qual equipe?")
      expect(estado['conferencia']).to include('correcao' => false)
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
      allow(builder).to receive(:aplicar_lista).and_wrap_original do |original, *args|
        vezes += 1
        raise erro if vezes == 2

        original.call(*args)
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

      expect(estado).to include('needs_more_info' => false, 'applied' => true, 'pergunta_pendente' => '')
    end

    it 'correção derrotada por um ajuste mais novo: avisa, não diz "não consegui aplicar"' do
      correcao_aplicada
      vezes = 0
      allow(builder).to receive(:aplicar_lista).and_wrap_original do |original, *args|
        vezes += 1
        Autonomia::Agents::BuildThread.create!(account: account, agent: agent) if vezes == 2
        original.call(*args)
      end

      run_turn

      expect(estado).to include('needs_more_info' => false, 'applied' => true, 'next_question' => texto(:correcao_superada),
                                'pergunta_pendente' => '')
    end

    it 'o agente mudou por outro caminho depois da primeira escrita: não corrige e avisa' do
      allow(conferente).to receive(:conferir) do |**kwargs|
        Autonomia::Agents::Agent.where(id: agent.id).update_all(updated_at: 1.minute.from_now) # rubocop:disable Rails/SkipsModelValidations
        conferencia_de(kwargs[:mudancas], nao: [1])
      end

      run_turn

      expect(calls.size).to eq(1)
      expect(estado).to include('needs_more_info' => false, 'applied' => true, 'next_question' => texto(:agente_mudou))
    end

    it 'passado o teto de tempo do turno, não corrige: o que faltou vira pergunta' do
      correcao_aplicada
      allow(conferente).to receive(:conferir) do |**kwargs|
        travel(described_class::FechamentoDoAjuste::LIMITE_PARA_CORRIGIR_S + 1)
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
end
