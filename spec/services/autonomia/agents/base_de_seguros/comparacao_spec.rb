require 'rails_helper'

# F3 do tema 8 (#1429): o antes e depois de "Atualizar com a nova base". As 3 perguntas do tipo da base NOVA, respondidas
# pelo agente como está hoje e com a base nova, pelo mesmo caminho do Testar, sem ferramenta (modo prova). Nada é gravado.
RSpec.describe Autonomia::Agents::BaseDeSeguros::Comparacao do
  let(:conta) { conta_da_fase2 }
  let(:bloco) { Autonomia::Segmentos::Bloco }
  let(:antiga) { { 'segmento' => 'seguros/seguradora', 'versao' => 'antiga000000', 'texto' => 'TEXTO ANTIGO' } }
  let(:agent) { criar_principal(conta, config: { 'with_knowledge' => false, 'base' => antiga }) }
  let(:chamadas) { [] }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AUTONOMIA_PACOTES_ENABLED: 'true') { example.run } }

  before do
    nicho = Autonomia::Agents::Nicho
    conta.update!(internal_attributes: conta.internal_attributes.to_h.merge(nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => 'corretora'))
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      texto = Autonomia::Agents::PromptParts::SegmentoDoAgente.texto(kwargs[:agent])
      agente = kwargs[:agent]
      chamadas << kwargs.merge(texto_da_base: texto, so_leitura: agente.readonly?, mudado: agente.changed?)
      instance_double(Autonomia::Agents::Answerer, answer: resposta(texto == 'TEXTO ANTIGO' ? 'com a antiga' : 'com a nova'))
    end
  end

  def resposta(texto, equipe: false, error: nil)
    Autonomia::Agents::AnswerResult.new(reply: texto, confidence: 1.0, handoff: { should: equipe, reason: nil }, used_knowledge: [],
                                        answered_from_knowledge: false, raw_reply: texto, error: error)
  end

  it 'responde as 3 perguntas do tipo novo com a base de hoje e com a nova' do
    resultado = described_class.new(agent, idioma: 'pt_BR').rodar

    perguntas = bloco.perguntas('seguros/corretora', 'pt_BR')
    expect(resultado[:perguntas].pluck(:pergunta)).to eq(perguntas)
    expect(resultado[:perguntas].pluck(:hoje)).to all(eq('com a antiga'))
    expect(resultado[:perguntas].pluck(:nova)).to all(eq('com a nova'))
    expect(chamadas.size).to eq(6)
    expect(resultado[:versao]).to eq(bloco.versao('seguros/corretora'))
  end

  it 'usa o motor do Testar sem ferramenta, com a etiqueta de custo do Testar' do
    described_class.new(agent, idioma: 'pt_BR').rodar

    expect(chamadas).to all(include(prova: true, feature: Autonomia::Agents::Playground::USAGE_FEATURE))
    expect(chamadas.pluck(:texto_da_base).uniq).to contain_exactly('TEXTO ANTIGO', bloco.for_segmento('seguros/corretora'))
  end

  it 'não grava nada no agente' do
    antes = agent.reload.attributes

    described_class.new(agent, idioma: 'pt_BR').rodar

    expect(agent.reload.attributes).to eq(antes)
    expect(agent.instruction_versions).to be_empty
    # A base nova vai numa cópia só de leitura, mudada só na memória; o agente de hoje vai como está.
    novas = chamadas.reject { |chamada| chamada[:texto_da_base] == 'TEXTO ANTIGO' }
    expect(novas).to all(include(so_leitura: true, mudado: true))
    expect(chamadas - novas).to all(include(so_leitura: false, mudado: false))
  end

  it 'pergunta no idioma de quem pediu' do
    resultado = described_class.new(agent, idioma: 'en').rodar

    expect(resultado[:perguntas].pluck(:pergunta)).to eq(bloco.perguntas('seguros/corretora', 'en'))
  end

  it 'quando o agente passaria para a equipe sem texto, diz isso' do
    allow(Autonomia::Agents::Answerer).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Answerer, answer: resposta(nil, equipe: true)))

    item = described_class.new(agent, idioma: 'pt_BR').rodar[:perguntas].first

    expect(item).to include(hoje: nil, hoje_equipe: true, nova: nil, nova_equipe: true)
  end

  it 'falha da IA: levanta Falhou e libera o agente para tentar de novo' do
    allow(Autonomia::Agents::Answerer).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Answerer, answer: resposta(nil, error: 'ai_unavailable')))
    limite = Autonomia::Agents::BaseDeSeguros::Limite
    limite.reservar!(agent)

    expect { described_class.new(agent, idioma: 'pt_BR').rodar }.to raise_error(described_class::Falhou)
    expect { limite.reservar!(agent) }.not_to raise_error
  end

  it 'sem base nova (em dia), não compara' do
    agent.update!(config: agent.config.merge('base' => { 'segmento' => 'seguros/corretora', 'versao' => bloco.versao('seguros/corretora'),
                                                         'texto' => bloco.for_segmento('seguros/corretora') }))

    expect { described_class.new(agent, idioma: 'pt_BR').rodar }.to raise_error(described_class::SemBaseNova)
    expect(chamadas).to be_empty
  end

  it 'qualquer outra falha também libera o agente (a base ficou em dia entre o pedido e o job)' do
    limite = Autonomia::Agents::BaseDeSeguros::Limite
    limite.reservar!(agent)
    agent.update!(config: agent.config.merge('base' => { 'segmento' => 'seguros/corretora', 'versao' => bloco.versao('seguros/corretora'),
                                                         'texto' => bloco.for_segmento('seguros/corretora') }))

    expect { described_class.new(agent, idioma: 'pt_BR').rodar }.to raise_error(described_class::SemBaseNova)
    expect { limite.reservar!(agent) }.not_to raise_error
  end

  # Sem stub do Answerer: o caminho real em modo prova, só a ida ao modelo é trocada.
  describe 'com o Answerer de verdade' do
    let(:pedidos) { [] }

    before do
      allow(Autonomia::Agents::Answerer).to receive(:new).and_call_original
      allow(Crm::Ai::CredentialResolver).to receive(:new)
        .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', api_base: 'https://api.openai.com', source: :system }))
      allow_any_instance_of(Crm::Ai::ResponsesClient).to receive(:create_with_tool_executor) do |_cliente, **kwargs| # rubocop:disable RSpec/AnyInstance
        pedidos << kwargs
        { text: { reply: 'ok', confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                  answered_from_knowledge: false }.to_json, usage: {} }
      end
    end

    it 'não manda ferramenta ao modelo, troca só a base e não grava nada' do
      antes = agent.reload.attributes

      resultado = described_class.new(agent, idioma: 'pt_BR').rodar

      expect(resultado[:perguntas].pluck(:hoje, :nova)).to all(eq(%w[ok ok]))
      expect(pedidos.size).to eq(6)
      expect(pedidos.pluck(:tools)).to all(be_blank)
      textos = pedidos.map { |pedido| pedido[:input].to_json }
      expect(textos.count { |texto| texto.include?('TEXTO ANTIGO') }).to eq(3)
      expect(textos.count { |texto| texto.include?('Ramo: corretora de seguros') }).to eq(3)
      expect(pedidos.pluck(:instructions).uniq.size).to eq(1)
      expect(agent.reload.attributes).to eq(antes)
    end
  end

  describe 'pela operação interativa (Crm::Ai::InteractiveJob)' do
    let(:dono) { create(:user, account: conta, role: :administrator) }

    def operacao(usuario)
      account_user = conta.account_users.find_by(user: usuario)
      Crm::Ai::InteractiveOperation.new('account_id' => conta.id, 'account_user_id' => account_user.id, 'operation' => 'agent_base_compare',
                                        'inputs' => { 'agent_id' => agent.id }, 'locale' => 'pt_BR')
    end

    it 'quem gerencia recebe as perguntas comparadas' do
      op = operacao(dono)
      op.authorize!

      expect(op.perform[:perguntas].size).to eq(3)
    end

    it 'quem só vê é recusado' do
      usuario = create(:user, account: conta, role: :agent)
      usuario.account_users.find_by(account: conta).update!(custom_role: create(:custom_role, account: conta, permissions: %w[autonomia_view]))

      expect { operacao(usuario).authorize! }.to raise_error(Pundit::NotAuthorizedError)
    end

    it 'sem a Fase 2 é recusado' do
      Autonomia::Agents::Fase2.desligar!(conta)

      expect { operacao(dono).authorize! }.to raise_error(Pundit::NotAuthorizedError)
    end
  end
end
