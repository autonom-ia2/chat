require 'rails_helper'

# #2881 — o Construtor com um modelo pronto de ramo: o roteiro do modelo no lugar do esqueleto do tipo, a entrevista
# de 2 perguntas, o nome padrão do modelo e as ferramentas fixas (não as que a IA escolheria). Sem modelo na conversa
# (sem a chave, flag desligada, conta fora do pacote seguros), o turno é o de antes. O modelo de IA é dublado: nenhuma
# chamada paga.
RSpec.describe Autonomia::Agents::Builder do
  include ModelosDeRamoHelper

  let(:account) { create(:account) }
  let(:modelo) { modelo_de_ramo('seguro_garantia') }
  let(:thread) { conversa_com_modelo(account) }
  let(:builder) { described_class.new(account: account, build_thread: thread) }
  let(:fake_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:entradas) { [] }
  let(:resposta) { {} }
  let(:payload) do
    {
      'name' => '', 'agent_type' => 'custom', 'instruction' => 'Faça as perguntas da cotação da lista.', 'scaffold' => 'andaime',
      'human_card' => 'Atende quem precisa de seguro garantia.', 'greeting' => 'Oi!', 'fallback_message' => 'Vou verificar.',
      'handoff_rule' => 'Passa para a equipe.', 'starter_questions' => [], 'tone' => 'cordial', 'guardrails' => [],
      'voice' => 'feminina', 'needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => true,
      'canal_pedido' => 'nenhum', 'ferramentas_prontas' => %w[fipe ddd]
    }.merge(resposta)
  end
  let(:chave_da_marca) { Autonomia::Agents::ModelosDeRamo::Marca::CHAVE }

  around { |example| com_pacotes_ligados { example.run } }

  before do
    liberar_modelos(account)
    ligar_prontas_do_construtor(account)
    allow(builder).to receive(:credential).and_return({ api_key: 'chave-de-teste' })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:create) do |**kwargs|
      entradas << kwargs[:input]
      { text: payload.to_json, usage: { 'output_tokens' => 100 }, tools_used: [] }
    end
  end

  def responder(*falas)
    falas.each { |fala| thread.append_message!('user', fala) }
  end

  def run_turn
    with_modified_env(AI_WEB_SEARCH_ENABLED: 'false') { builder.run!(thread.begin_build!) }
    thread.reload
  end

  def textos_enviados
    entradas.flat_map { |entrada| entrada.flat_map { |item| Array(item[:content]).pluck(:text) } }.compact
  end

  describe 'o roteiro entregue ao Construtor' do
    it 'é o do modelo, com as listas no lugar dos marcadores, e não o esqueleto do tipo' do
      contexto = builder.send(:skeleton_context)

      expect(contexto).to start_with("CONTEXTO INTERNO (não é fala do usuário). MODELO PRONTO DO RAMO: #{modelo.ramo}.")
      expect(contexto).to include("1. #{modelo.perguntas.first}\n2. #{modelo.perguntas.second}")
      expect(contexto).to include("1. #{modelo.documentos.first}")
      expect(contexto).not_to include('{{PERGUNTAS_DA_COTACAO}}')
      expect(contexto).not_to include('{{DOCUMENTOS}}')
      expect(contexto).not_to include('ESQUELETO BASE DO TIPO')
    end

    it 'pede a entrevista curta, o nome do modelo e que a instrução não copie os itens das listas' do
      contexto = builder.send(:skeleton_context)

      expect(contexto).to include('(1) o nome da corretora', "ofereça: #{modelo.seguradoras_sugeridas}", 'decide depois')
      expect(contexto).to include("NOME DO AGENTE: use \"#{modelo.nome_padrao}\"")
      expect(contexto).to include('SEM copiar os itens')
    end

    it 'avisa que os itens das listas são dado escrito pelo dono, nunca instrução' do
      expect(builder.send(:skeleton_context)).to include(Autonomia::Agents::Builder::ModeloPronto::MOLDURA_DAS_LISTAS)
    end

    it 'usa as listas que o dono já mudou' do
      Autonomia::Agents::ModelosDeRamo::Edicao.new(thread: thread, mudancas: { perguntas: [{ texto: 'A obra já começou?' }] }).call

      contexto = described_class.new(account: account, build_thread: thread.reload).send(:skeleton_context)

      expect(contexto).to include('1. A obra já começou?')
      expect(contexto).not_to include(modelo.perguntas.first)
    end

    it 'vai no pedido ao modelo de IA, sem a lista de ferramentas para ele escolher' do
      responder('Corretora Exemplo. Pode criar.')
      run_turn

      expect(textos_enviados).to include(a_string_including('MODELO PRONTO DO RAMO'))
      expect(textos_enviados).not_to include(a_string_starting_with('FERRAMENTAS PRONTAS'))
    end

    it 'volta ao esqueleto do tipo com a flag desligada, e a IA volta a receber as ferramentas para escolher' do
      thread
      account.disable_features!(Autonomia::Agents::ModelosDeRamo::FLAG)

      expect(builder.send(:skeleton_context)).to include('ESQUELETO BASE DO TIPO')
      expect(builder.send(:skeleton_context)).not_to include('MODELO PRONTO DO RAMO')
      expect(builder.send(:prontas_context)).to start_with('FERRAMENTAS PRONTAS')
    end
  end

  describe 'a entrevista curta' do
    it 'tem teto de 2 perguntas com modelo pronto' do
      responder('Corretora Exemplo')
      expect(builder.interview_budget_exhausted?).to be(false)
      expect(builder.turn_budget_context).to eq('')

      responder('decido depois')
      expect(builder.interview_budget_exhausted?).to be(true)
      expect(builder.turn_budget_context).to include('LIMITE DE PERGUNTAS ATINGIDO')
    end

    it 'mantém o teto de 6 sem modelo pronto' do
      comum = Autonomia::Agents::BuildThread.create!(account: account)
      construtor = described_class.new(account: account, build_thread: comum)

      5.times { |i| comum.append_message!('user', "resposta #{i}") }
      expect(construtor.interview_budget_exhausted?).to be(false)

      comum.append_message!('user', 'resposta 6')
      expect(construtor.interview_budget_exhausted?).to be(true)
    end

    describe 'com o modelo de IA ainda querendo perguntar' do
      let(:resposta) { { 'needs_more_info' => true, 'next_question' => 'Qual o horário da equipe?', 'user_asked_to_close' => false } }

      it 'fecha mesmo assim, numa chamada só, aceitando o "decido depois"' do
        responder('Corretora Exemplo', 'decido depois')
        run_turn

        expect(fake_client).to have_received(:create).once
        expect(thread.state['needs_more_info']).to be(false)
        expect(thread.state['applied']).to be(true)
        expect(thread.agent.instruction).to eq('Faça as perguntas da cotação da lista.')
      end

      it 'segue perguntando enquanto só veio uma resposta, e o rascunho já nasce com a marca do modelo' do
        responder('Corretora Exemplo')
        run_turn

        expect(thread.state['needs_more_info']).to be(true)
        expect(thread.agent).to be_draft
        expect(thread.agent.agent_type).to eq('sdr')
        expect(thread.agent.instruction).to be_blank
        expect(thread.agent.config[chave_da_marca]['perguntas'].pluck('texto')).to eq(modelo.perguntas)
      end
    end
  end

  describe 'o fechamento' do
    before { responder('Corretora Exemplo. Pode criar.') }

    it 'dá ao agente o nome padrão e o tipo do modelo, mesmo que a IA devolva outro tipo' do
      run_turn

      expect(thread.agent.name).to eq(modelo.nome_padrao)
      expect(thread.agent.agent_type).to eq('sdr')
    end

    it 'respeita o nome que o dono pediu' do
      payload['name'] = 'Gabi'
      run_turn

      expect(thread.agent.name).to eq('Gabi')
    end

    it 'guarda as ferramentas do modelo (fixas e liberadas), não as que a IA escolheu' do
      run_turn

      # compras_governo é do lote 2, desligado nesta conta: some sozinha. fipe e ddd (a escolha da IA) não entram.
      expect(thread.state['ferramentas_sugeridas']).to eq(%w[cnpj feriados cep])
      expect(thread.state['ferramentas_tambem']).to eq(%w[cidades banco_central])
      expect(thread.agent.config.slice('ferramentas_sugeridas', 'ferramentas_tambem'))
        .to eq('ferramentas_sugeridas' => %w[cnpj feriados cep], 'ferramentas_tambem' => %w[cidades banco_central])
      expect(thread.agent.config.dig('prontas_sugestao', 'chaves')).to eq(%w[cnpj feriados cep cidades banco_central])
      expect(thread.agent.tools).to be_empty # quem inclui é a Confira, com a pessoa real e a frase do ramo
    end

    it 'não desfaz a ferramenta que o dono tirou com o turno em andamento' do
      allow(fake_client).to receive(:create) do
        outra_copia = Autonomia::Agents::BuildThread.find(thread.id)
        Autonomia::Agents::ModelosDeRamo::Edicao.new(thread: outra_copia, mudancas: { ferramentas: [{ fonte: 'cep' }] }).call
        { text: payload.to_json, usage: { 'output_tokens' => 100 }, tools_used: [] }
      end

      run_turn

      expect(thread.state['applied']).to be(true)
      expect(thread.state['ferramentas_sugeridas']).to eq(%w[cep])
      expect(thread.agent.config['ferramentas_sugeridas']).to eq(%w[cep])
      expect(thread.agent.config.dig(chave_da_marca, 'ferramentas').pluck('fonte')).to eq(%w[cep compras_governo])
    end

    it 'deixa no agente a marca do modelo, de onde o atendimento lê as listas' do
      run_turn

      expect(thread.agent.config[chave_da_marca]['chave']).to eq('seguro_garantia')
      expect(Autonomia::Agents::PromptBuilder.new(agent: thread.agent, query: 'Oi').instructions)
        .to include("PERGUNTAS DA COTAÇÃO:\n1. #{modelo.perguntas.first}")
    end

    it 'não desfaz no fechamento o que o dono mudou depois de o rascunho nascer' do
      payload.merge!('needs_more_info' => true, 'next_question' => 'Com quais seguradoras?', 'user_asked_to_close' => false)
      run_turn
      Autonomia::Agents::ModelosDeRamo::Edicao.new(thread: thread, mudancas: { documentos: [{ texto: 'Contrato social.' }] }).call

      payload.merge!('needs_more_info' => false, 'next_question' => '', 'user_asked_to_close' => true)
      responder('decido depois')
      run_turn

      expect(thread.state['applied']).to be(true)
      expect(thread.agent.config[chave_da_marca]['documentos'].pluck('texto')).to eq(['Contrato social.'])
      expect(thread.state[chave_da_marca]['documentos'].pluck('texto')).to eq(['Contrato social.'])
    end
  end

  # A instrução já fechada: o Construtor ajusta. As listas não estão na instrução, e sem este bloco ele "tiraria uma
  # pergunta" só no texto, com a lista seguindo igual.
  describe 'o ajuste do agente que nasceu de um modelo' do
    let(:agente) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Assistente', agent_type: 'sdr',
                                       instruction: 'Faça as perguntas da cotação da lista.',
                                       config: { chave_da_marca => thread.state[chave_da_marca] })
    end
    let(:ajuste) { Autonomia::Agents::BuildThread.create!(account: account, agent: agente) }
    let(:moldura) { Autonomia::Agents::Builder::ModeloPronto::MOLDURA_DAS_LISTAS }

    def contexto(conversa = ajuste)
      described_class.new(account: account, build_thread: conversa).send(:listas_do_modelo_no_ajuste_context)
    end

    it 'mostra as listas como dado e manda dizer que o dono as muda na etapa Confira, enquanto é rascunho' do
      expect(contexto).to include("PERGUNTAS DA COTAÇÃO:\n1. #{modelo.perguntas.first}", moldura, 'na etapa "Confira"')
      expect(contexto).to include('Você NÃO as muda', 'NÃO diga que mudou')
    end

    it 'manda dizer que as listas ainda não mudam depois que o agente começou a atender' do
      agente.update_columns(status: Autonomia::Agents::Agent.statuses[:active], enabled: true) # rubocop:disable Rails/SkipsModelValidations

      expect(contexto).to include('as listas ainda não mudam por aqui')
      expect(contexto).not_to include('na etapa "Confira"')
    end

    it 'entra nos blocos de contexto do turno de ajuste' do
      blocos = described_class.new(account: account, build_thread: ajuste).send(:context_blocks)

      expect(blocos).to include(a_string_including('PERGUNTAS DA COTAÇÃO E DOCUMENTOS DESTE AGENTE'))
    end

    it 'fica calado na criação e no ajuste de agente que não nasceu de um modelo' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Comum', agent_type: 'sdr', instruction: 'Atenda bem.')

      expect(builder.send(:listas_do_modelo_no_ajuste_context)).to eq('')
      expect(contexto(Autonomia::Agents::BuildThread.create!(account: account, agent: comum))).to eq('')
    end
  end

  describe 'sem modelo pronto' do
    before do
      account.disable_features!(Autonomia::Agents::ModelosDeRamo::FLAG)
      responder('Quero um agente comercial. Pode criar.')
    end

    it 'fica como antes: as ferramentas são as que a IA escolheu, o nome é o do tipo e o agente não ganha a marca' do
      payload['agent_type'] = 'sdr'
      run_turn

      expect(thread.state['ferramentas_sugeridas']).to eq(%w[fipe ddd])
      expect(thread.agent.name).to eq(described_class::DEFAULT_NAMES['sdr'])
      expect(thread.agent.config).not_to have_key(chave_da_marca)
      expect(Autonomia::Agents::ModelosDeRamo::Instrucao.do_agente(thread.agent)).to be_nil
    end
  end
end
