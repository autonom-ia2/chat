require 'rails_helper'

# #1428 (tema 6, entrega C) — as respostas prontas que vão com a pergunta do "Mudar conversando". Só a pergunta do
# MODELO leva as opções que o próprio modelo escreveu; a pergunta de conflito, que o código abre, leva os dois botões
# fixos dele (o código sabe que é ela pelo caminho, nunca pelo texto). Qualquer outro fim de turno zera as opções.
RSpec.describe Autonomia::Agents::Builder do
  include_context 'with ajuste por lista'

  let(:opcoes) { ['Passar para a equipe', 'Dizer R$ 99 por mês'] }

  def opcoes_no_estado
    estado['opcoes_de_resposta']
  end

  # Revisão crítica da entrega C (BAIXO 2): toda vez que há opções, a última mensagem da conversa é a pergunta que as
  # trouxe (o `next_question` do state, que a tela compara com ela).
  def expect_pergunta_por_ultimo
    expect(thread.reload.messages.last['content']).to eq(estado['next_question'])
  end

  describe 'o schema do ajuste' do
    it 'pede até 4 opções, obrigatórias no schema estrito' do
      schema = described_class::AjustePorLista::SCHEMA[:schema]

      expect(schema[:required]).to include('opcoes_de_resposta')
      expect(schema[:properties][:opcoes_de_resposta]).to include(type: 'array', maxItems: 4, items: { type: 'string' })
    end
  end

  # Série do t6d anulada (c_opcoes_passagem_vaga): com o pedido vago de passagem, o Construtor ofereceu como opção a regra
  # que o agente já tem. A causa raiz é o pedido ao modelo: cada opção muda algo de fato, contra a configuração atual que
  # ele recebe no mesmo turno. Quem decide se a opção repete a regra é o modelo, nunca o código.
  describe 'as opções mudam algo de fato' do
    it 'a descrição: opção que muda algo não repete a regra atual; a mesma direção vale; deixar como está, quando faz sentido' do
      descricao = described_class::OpcoesDeResposta::DESCRIPTION
      expect(descricao).to include('Uma opcao que muda algo nunca repete a regra atual tal como esta',
                                   'compare com a CONFIGURACAO ATUAL DO AGENTE', 'o tom de hoje nao entra como opcao',
                                   'ir na mesma direcao de hoje vale se muda algo (ex.: mais curto que hoje)',
                                   'Uma opcao de deixar como esta vale quando fizer sentido')
      expect(descricao).not_to include('passa para a equipe, e a regra de hoje')
    end

    it 'o turno do ajuste leva a regra de passagem atual na configuração atual, junto com o schema das opções' do
      respostas << saida('needs_more_info' => true, 'next_question' => 'Em que situações passar?', 'opcoes_de_resposta' => opcoes)

      run_turn

      contexto = calls.first[:input].flat_map { |item| Array(item[:content]) }.pluck(:text).join("\n")
      expect(contexto).to include('CONFIGURAÇÃO ATUAL DO AGENTE:', "handoff_rule: #{agent.handoff_rule}")
      expect(calls.first[:schema][:schema][:properties][:opcoes_de_resposta][:description])
        .to eq(described_class::OpcoesDeResposta::DESCRIPTION)
    end
  end

  describe 'OpcoesDeResposta.filtrar' do
    def opcoes_de(valor)
      described_class::OpcoesDeResposta.filtrar('opcoes_de_resposta' => valor)
    end

    it 'fica com até 4, sem espaço sobrando, vazias ou repetidas' do
      expect(opcoes_de([' Sim ', '', 'Não', 'Sim', 'Talvez', 'Depois', 'Nunca'])).to eq(%w[Sim Não Talvez Depois])
    end

    it 'descarta a opção longa demais em vez de cortar a frase' do
      longa = 'a' * (described_class::OpcoesDeResposta::MAX_CHARS + 1)

      expect(opcoes_de(['Sim', longa, 'Não'])).to eq(%w[Sim Não])
    end

    # Revisão adversarial da entrega C (2): o texto passa pelo TextoSemDisfarce (#1669) antes do tamanho e das repetidas.
    it 'tira os invisíveis de formato e descarta a que só tinha espaço invisível' do
      tags = (0xE0020..0xE007F).first(5).pack('U*')
      escritas = ["Sim#{tags}", "N\u200Bão", "\u202EAgora", "\u00A0\u3164", 'Sim', "Mais\u00A0tarde"]

      expect(opcoes_de(escritas)).to eq(['Sim', 'Não', 'Agora', 'Mais tarde'])
    end

    it 'a que fica longa só por invisíveis não é descartada pelo tamanho' do
      invisiveis = "\u200B" * described_class::OpcoesDeResposta::MAX_CHARS

      expect(opcoes_de(["Sim#{invisiveis}", 'Não'])).to eq(%w[Sim Não])
    end

    it 'com menos de duas não há escolha: nenhuma' do
      expect(opcoes_de(['Sim'])).to eq([])
      expect(opcoes_de('Sim')).to eq([])
      expect(opcoes_de(nil)).to eq([])
    end
  end

  describe 'quando o modelo pede esclarecimento sem mudar nada' do
    it 'a pergunta dele vai com as opções dele' do
      respostas << saida('needs_more_info' => true, 'next_question' => 'Que preço ele deve dizer?', 'opcoes_de_resposta' => opcoes)

      run_turn

      expect(estado).to include('needs_more_info' => true, 'applied' => false, 'opcoes_de_resposta' => opcoes)
      expect_pergunta_por_ultimo
      expect(thread.messages.last).to include('role' => 'assistant', 'content' => 'Que preço ele deve dizer?')
    end
  end

  describe 'quando não há pergunta do modelo no fim do turno' do
    it 'a resposta a uma pergunta do dono não leva opções' do
      respostas << saida('so_pergunta' => true, 'needs_more_info' => true, 'next_question' => 'Ele atende clientes.',
                         'opcoes_de_resposta' => opcoes)

      run_turn

      expect(opcoes_no_estado).to eq([])
    end

    it 'o esclarecimento sem texto cai no texto fixo, sem as opções do modelo' do
      respostas << saida('needs_more_info' => true, 'next_question' => ' ', 'opcoes_de_resposta' => opcoes)

      run_turn

      expect(estado['next_question']).to eq(texto(:sem_pedido))
      expect(opcoes_no_estado).to eq([])
    end

    it 'o texto fixo do código (nada a mudar) não leva opções' do
      respostas << saida('opcoes_de_resposta' => opcoes)

      run_turn

      expect(estado['next_question']).to eq(texto(:sem_pedido))
      expect(opcoes_no_estado).to eq([])
    end

    it 'aplicado sem pergunta: nenhuma opção, mesmo que o modelo tenha escrito' do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone')], 'opcoes_de_resposta' => opcoes)

      run_turn

      expect(estado).to include('applied' => true, 'needs_more_info' => false, 'opcoes_de_resposta' => [])
    end

    it 'o turno seguinte sem pergunta zera as opções do anterior' do
      respostas << saida('needs_more_info' => true, 'next_question' => 'Que preço?', 'opcoes_de_resposta' => opcoes)
      run_turn
      thread.append_message!('user', 'Deixe o tom curto')
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone')])

      described_class.new(account: account, build_thread: thread.reload).tap do |outro|
        allow(outro).to receive_messages(credential: { api_key: 'k' }, client: fake_client, cliente_da_correcao: fake_client)
        outro.run!(thread.begin_build!)
      end

      expect(opcoes_no_estado).to eq([])
    end
  end

  describe 'quando parte entra e o modelo pergunta sobre o resto' do
    it 'o cartão sai e a pergunta dele vai com as opções dele' do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone')], 'needs_more_info' => true,
                         'next_question' => 'E o preço, que valor?', 'opcoes_de_resposta' => opcoes)

      run_turn

      expect(estado).to include('applied' => true, 'parcial' => true, 'next_question' => 'E o preço, que valor?',
                                'opcoes_de_resposta' => opcoes)
      expect_pergunta_por_ultimo
    end

    it 'a escrita que não muda nada, com pergunta do modelo, também leva as opções dele' do
      respostas << saida('mudancas' => [mudanca('tone')], 'needs_more_info' => true, 'next_question' => 'Mais curto quanto?',
                         'opcoes_de_resposta' => opcoes)

      run_turn

      expect(estado).to include('applied' => false, 'next_question' => 'Mais curto quanto?', 'opcoes_de_resposta' => opcoes)
      expect_pergunta_por_ultimo
    end
  end

  describe 'quando o turno é retomado com o mesmo token' do
    it 'a pergunta guardada no ajuste em curso volta com as opções dela' do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone')], 'needs_more_info' => true,
                         'next_question' => 'E o preço?', 'opcoes_de_resposta' => opcoes)
      conferencias << RuntimeError.new('o job caiu')
      token = thread.begin_build!
      expect { builder.run!(token) }.to raise_error(RuntimeError)
      expect(estado.dig('ajuste_em_curso', 'resposta', 'opcoes_de_resposta')).to eq(opcoes)

      described_class.new(account: account, build_thread: thread.reload).tap do |retomada|
        allow(retomada).to receive_messages(credential: { api_key: 'k' }, client: fake_client)
        retomada.run!(token)
      end

      expect(calls.size).to eq(1)
      expect(estado).to include('next_question' => 'E o preço?', 'opcoes_de_resposta' => opcoes)
      expect_pergunta_por_ultimo
    end
  end

  describe 'quando tudo o que entrou não tinha sido pedido e foi desfeito' do
    it 'a pergunta do modelo depois do aviso leva as opções dele' do
      respostas << saida('human_card' => 'Outro cartão.', 'mudancas' => [mudanca('human_card', 'explica', 'Reescrevi o cartão.')],
                         'needs_more_info' => true, 'next_question' => 'O que você quer mudar?', 'opcoes_de_resposta' => opcoes)
      allow(conferente).to receive(:conferir) do |**kwargs|
        conferencia_de(kwargs[:mudancas]).then do |conf|
          conf.merge('itens' => conf['itens'].map { |item| item.merge('pedido_pelo_dono' => false) })
        end
      end

      run_turn

      expect(estado.dig('conferencia', 'desfeito', 'ok')).to be(true)
      expect(estado).to include('next_question' => 'O que você quer mudar?', 'opcoes_de_resposta' => opcoes)
      expect_pergunta_por_ultimo
    end
  end

  describe 'quando a conferência acha item não atendido' do
    let(:preco) { 'preço passa para a equipe' }
    let(:fala) { "Responda em no máximo 2 frases e #{preco}" }

    before do
      respostas << saida('tone' => 'cordial e curto',
                         'mudancas' => [mudanca('tone', 'no máximo 2 frases'), mudanca('handoff_rule', preco)])
      conferencias << { nao: [1] }
    end

    it 'a explicação da correção vai com as opções da correção' do
      respostas << saida('needs_more_info' => true, 'next_question' => 'Qual equipe?', 'opcoes_de_resposta' => opcoes)

      run_turn

      expect(estado).to include('next_question' => "#{texto(:nao_consegui, pedidos: preco)} Qual equipe?",
                                'opcoes_de_resposta' => opcoes)
      expect_pergunta_por_ultimo
    end

    it 'a correção aplicada que ainda pergunta leva as opções dela, não as da primeira escrita' do
      respostas[0] = respostas[0].merge('opcoes_de_resposta' => ['Velha 1', 'Velha 2'])
      respostas << saida('handoff_rule' => 'Preço vai à equipe.', 'mudancas' => [mudanca('handoff_rule', preco)],
                         'needs_more_info' => true, 'next_question' => 'Qual equipe?', 'opcoes_de_resposta' => opcoes)

      run_turn

      expect(estado['conferencia']).to include('correcao' => true)
      expect(estado).to include('next_question' => 'Qual equipe?', 'opcoes_de_resposta' => opcoes)
      expect_pergunta_por_ultimo
    end

    it 'a pergunta genérica do código, sem explicação do modelo, não leva opções' do
      respostas << saida('handoff_rule' => 'Preço vai à equipe.', 'mudancas' => [mudanca('handoff_rule', preco)],
                         'opcoes_de_resposta' => opcoes)
      conferencias << { nao: [2] }

      run_turn

      expect(estado['next_question']).to eq("#{texto(:nao_consegui, pedidos: preco)} #{texto(:de_outro_jeito)}")
      expect(opcoes_no_estado).to eq([])
    end
  end

  describe 'quando só há conflito, com tudo atendido' do
    it 'a pergunta do código leva os dois botões fixos, no idioma de quem conversa' do
      respostas << saida('tone' => 'curto', 'mudancas' => [mudanca('tone', 'curto')], 'opcoes_de_resposta' => opcoes)
      conferencias << { conflito: true }

      run_turn

      expect(estado).to include('next_question' => texto(:conflito, pedidos: 'curto'),
                                'opcoes_de_resposta' => [texto('opcoes_do_conflito.manter'),
                                                         texto('opcoes_do_conflito.mudar')])
      expect_pergunta_por_ultimo
    end
  end

  # Revisão crítica da entrega C (1): o turno legado esquece as opções que o piloto deixou; religar não as traz de volta.
  it 'piloto desligado, turno legado, piloto religado: a conversa não traz as opções velhas' do
    respostas << saida('needs_more_info' => true, 'next_question' => 'Que preço?', 'opcoes_de_resposta' => opcoes)
    run_turn
    Autonomia::Agents::Fase2.desligar!(account)
    thread.append_message!('user', 'Troque a saudação')
    respostas << saida('greeting' => 'Olá')
    described_class.new(account: account.reload, build_thread: thread.reload).tap do |legado|
      allow(legado).to receive_messages(credential: { api_key: 'k' }, client: fake_client)
      legado.run!(thread.begin_build!)
    end
    Autonomia::Agents::Fase2.ligar!(account)

    corpo = ApplicationController.render(template: 'api/v1/accounts/autonomia/agents/build_threads/show', formats: [:json],
                                         assigns: { thread: thread.reload })

    expect(estado).not_to have_key('opcoes_de_resposta')
    expect(JSON.parse(corpo).dig('payload', 'state')).not_to have_key('opcoes_de_resposta')
  end

  it 'mark_failed! zera as opções' do
    token = thread.begin_build!
    thread.mark_ready!(token, state: { 'opcoes_de_resposta' => opcoes })
    token = thread.begin_build!

    thread.mark_failed!(token, 'build_error')

    expect(opcoes_no_estado).to be_nil
  end
end
