require 'rails_helper'

# #1428 (revisão crítica da entrega B, cena W4) — o fechamento do turno junta o state novo ao que está NO BANCO, no
# próprio UPDATE guardado, em vez de regravar o state inteiro a partir da cópia em memória. O que outro caminho grava no
# meio do turno (a prova do ajuste, a marca do Desfazer) sobrevive. Fora disso, o state final é exatamente o de antes:
# a cópia em memória mesclada com o que o turno escreveu (a fórmula antiga), em criação, ajuste legado e Lia.
RSpec.describe Autonomia::Agents::BuildThread do
  include_context 'with ajuste por lista'

  let(:builder) { Autonomia::Agents::Builder.new(account: account, build_thread: thread) }
  let(:conferidas) { [] }
  let(:argumento_de) do
    { mark_ready!: ->(nomeados, _) { nomeados[:state] }, guardar_no_estado!: ->(_, posicional) { posicional },
      esquecer_do_estado!: ->(_, posicional) { posicional }, mark_failed!: ->(_, posicional) { posicional } }
  end

  # A fórmula de antes, em Ruby, sobre a cópia em memória: o que cada escrita gravava.
  def formula_antiga(atual, metodo, args)
    case metodo
    when :mark_ready!, :guardar_no_estado! then atual.merge(args)
    when :esquecer_do_estado! then atual.except(*args)
    when :mark_failed! then atual.merge(%w[ajuste_em_curso nao_pedido_anterior].select { |chave| atual.key?(chave) }.index_with(nil))
                                 .merge('error' => args, 'error_fields' => [], 'applied' => false)
    end
  end

  # Cada escrita do turno é conferida: o state do banco depois dela é a fórmula antiga aplicada à memória de antes.
  def conferir_escritas!(alvo)
    argumento_de.each do |metodo, argumento|
      allow(alvo).to receive(metodo).and_wrap_original do |original, token, *posicionais, **nomeados|
        antes = alvo.state.to_h.deep_dup
        original.call(token, *posicionais, **nomeados).tap do |venceu|
          anotar(alvo, metodo, antes, argumento.call(nomeados, posicionais.first)) if venceu
        end
      end
    end
  end

  def anotar(alvo, metodo, antes, args)
    conferidas << [metodo, alvo.reload.state, JSON.parse(formula_antiga(antes, metodo, args).to_json)]
  end

  def todas_iguais
    expect(conferidas).not_to be_empty
    conferidas.each { |metodo, banco, antiga| expect(banco).to eq(antiga), "#{metodo}: #{banco} != #{antiga}" }
  end

  describe 'fora do piloto, o state final é o de antes' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'na criação' do
      sem_agente = described_class.create!(account: account, state: { 'agent_type' => 'support', 'no_materials_declared' => true })
      sem_agente.append_message!('user', 'Quero um agente de suporte')
      respostas << saida('needs_more_info' => true, 'next_question' => 'Qual o nome?')
      respostas << saida('needs_more_info' => false, 'name' => 'Bia')
      conferir_escritas!(sem_agente)
      criacao = Autonomia::Agents::Builder.new(account: account, build_thread: sem_agente)
      allow(criacao).to receive_messages(credential: { api_key: 'chave-de-teste' }, client: fake_client)

      criacao.run!(sem_agente.begin_build!)
      sem_agente.append_message!('user', 'Bia, pode fechar')
      criacao.run!(sem_agente.begin_build!)

      todas_iguais
      expect(sem_agente.reload.state).to include('no_materials_declared' => true, 'agent_type' => 'support')
    end

    it 'no ajuste legado, inclusive tirando as chaves do piloto' do
      thread.update!(state: { 'ajuste_em_curso' => { 'token' => 'velho' }, 'pendencia_turnos' => 2, 'no_materials_declared' => true })
      respostas << saida('greeting' => 'Olá!')
      conferir_escritas!(thread)

      run_turn

      todas_iguais
      expect(conferidas.map(&:first)).to include(:esquecer_do_estado!, :mark_ready!)
      expect(estado).not_to have_key('ajuste_em_curso')
    end

    # A Lia tem a instrução mantida: o Construtor recusa a escrita, e o SubmitJob marca a falha (mark_failed!).
    it 'na Lia (insurance_quote): a recusa vira falha com o state de antes' do
      agent.update_columns(agent_type: 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations
      thread.update!(state: { 'turn' => 2, 'no_materials_declared' => true })
      respostas << saida('agent_type' => 'insurance_quote', 'greeting' => 'Olá, sou a Lia.')
      conferir_escritas!(thread)
      token = thread.begin_build!

      expect { run_turn(token) }.to raise_error(Autonomia::Agents::Agent::InstrucaoMantida)
      thread.mark_failed!(token, 'build_error')

      todas_iguais
      expect(conferidas.map(&:first)).to eq([:mark_failed!])
    end

    it 'na falha: as chaves do piloto viram null e o erro entra, como antes' do
      thread.update!(state: { 'ajuste_em_curso' => { 'token' => 't' }, 'turn' => 3 })
      token = thread.begin_build!
      antes = thread.state.deep_dup

      thread.mark_failed!(token, 'build_error')

      expect(thread.reload.state).to eq(JSON.parse(formula_antiga(antes, :mark_failed!, 'build_error').to_json))
    end
  end

  describe 'o que outro caminho grava no meio do turno sobrevive' do
    # O bloco roda depois que este método voltou (dentro do stub): por isso vai como Proc, e não por yield.
    def no_meio_do_turno(&escrita)
      allow(fake_client).to receive(:create) do |**params|
        calls << params
        escrita.call # rubocop:disable Performance/RedundantBlockCall
        { text: (respostas.shift || saida).to_json, usage: {}, tools_used: [] }
      end
    end

    def aplicar_ajuste
      respostas << saida('tone' => 'cordial e curto', 'mudancas' => [mudanca('tone', fala, 'Respostas curtas.')],
                         'perguntas_de_prova' => ['Quais seguros?'])
      run_turn
    end

    # W4: o dono pergunta enquanto a prova roda; a prova grava no meio do turno da pergunta e não pode sumir.
    it 'W4: a prova gravada durante a pergunta do dono continua lá depois do turno' do
      aplicar_ajuste
      thread.append_message!('user', 'O que ele faz hoje?')
      respostas << saida('so_pergunta' => true, 'next_question' => 'Atende os clientes.')
      pronta = estado['prova'].merge('status' => 'pronta', 'ok' => 1, 'total' => 1)
      no_meio_do_turno do
        described_class.where(id: thread.id).update_all(["state = jsonb_set(state, '{prova}', ?::jsonb)", pronta.to_json]) # rubocop:disable Rails/SkipsModelValidations
      end

      run_turn

      expect(estado['prova']).to eq(pronta)
      expect(estado).to include('so_pergunta' => true, 'next_question' => 'Atende os clientes.')
    end

    it 'a marca de desfeito do último ajuste, gravada no meio do turno, sobrevive' do
      aplicar_ajuste
      thread.append_message!('user', 'O que ele faz hoje?')
      respostas << saida('so_pergunta' => true, 'next_question' => 'Atende os clientes.')
      no_meio_do_turno do
        described_class.where(id: thread.id)
                       .update_all("state = jsonb_set(state, '{ultimo_ajuste,desfeito}', 'true'::jsonb)") # rubocop:disable Rails/SkipsModelValidations
      end

      run_turn

      expect(estado.dig('ultimo_ajuste', 'desfeito')).to be(true)
    end

    # Revisão (mutante m6): a escrita do ajuste em curso parte do banco, não da cópia lida no começo do turno.
    def marcar_desfeito_por_fora!
      described_class.where(id: thread.id)
                     .update_all("state = jsonb_set(state, '{ultimo_ajuste}', '{\"desfeito\": true}'::jsonb)") # rubocop:disable Rails/SkipsModelValidations
    end

    it 'guardar_no_estado!: a marca do Desfazer gravada entre a leitura e a gravação sobrevive' do
      token = thread.begin_build!
      marcar_desfeito_por_fora!

      expect(thread.guardar_no_estado!(token, 'ajuste_em_curso' => { 'token' => token })).to be(true)

      expect(estado).to include('ultimo_ajuste' => { 'desfeito' => true }, 'ajuste_em_curso' => { 'token' => token })
    end

    it 'esquecer_do_estado!: tira só a chave pedida e deixa a marca gravada por fora' do
      thread.update!(state: { 'ajuste_em_curso' => { 'token' => 'velho' } })
      token = thread.begin_build!
      marcar_desfeito_por_fora!

      expect(thread.esquecer_do_estado!(token, ['ajuste_em_curso'])).to be(true)

      expect(estado).to eq('ultimo_ajuste' => { 'desfeito' => true })
    end

    it 'a escrita do turno perdido (token velho) não grava nada' do
      token = thread.begin_build!
      travel_to(10.minutes.from_now) { thread.begin_build! }

      expect(thread.mark_ready!(token, state: { 'turn' => 9 })).to be(false)
      expect(thread.reload.state).not_to have_key('turn')
    end
  end
end
