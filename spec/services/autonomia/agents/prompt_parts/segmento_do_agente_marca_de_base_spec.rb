require 'rails_helper'

# MARCA DE BASE (#1429): o agente nasce com `config['base'] = { segmento, versao, texto }` e recebe sempre o texto
# GRAVADO. Nem a troca de tipo da conta nem uma edição nossa do texto muda agente existente: só o botão (F3).
RSpec.describe Autonomia::Agents::PromptParts::SegmentoDoAgente do
  let(:account) { conta_da_fase2 }
  let(:gravada) { { 'segmento' => 'seguros/corretora', 'versao' => 'v1', 'texto' => 'TEXTO GRAVADO' } }
  let(:sem_texto) { { 'segmento' => 'seguros/corretora', 'versao' => nil, 'texto' => nil } }
  let(:history) { [{ role: 'user', content: 'Oi' }] }

  around do |example|
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    account.update!(internal_attributes: account.internal_attributes.to_h.merge(
      Autonomia::Agents::Nicho::NICHO_KEY => 'seguros', Autonomia::Agents::Nicho::PERFIL_KEY => 'corretora'
    ))
  end

  def criar_agente(config)
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: config)
  end

  def stub_bloco_atual(prefixo)
    allow(Autonomia::Segmentos::Bloco).to receive(:for_segmento) { |seg| seg && "#{prefixo} #{seg}" }
    allow(Autonomia::Segmentos::Bloco).to receive(:versao) { |seg| seg && "v-#{prefixo}" }
  end

  def input_de(agente)
    Autonomia::Agents::PromptBuilder.new(agent: agente, query: 'Quanto custa?', history: history).input
  end

  def textos(input)
    input.flat_map { |item| item[:content].map { |parte| parte[:text] } }.join("\n")
  end

  describe Autonomia::Segmentos::Bloco do
    it 'segmento é a camada mais específica da conta' do
      expect(described_class.segmento(account)).to eq('seguros/corretora')
    end

    it 'segmento é nil com o interruptor desligado ou na conta geral' do
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) { expect(described_class.segmento(account)).to be_nil }
      account.update!(internal_attributes: account.internal_attributes.to_h.merge(Autonomia::Agents::Nicho::NICHO_KEY => 'geral'))
      expect(described_class.segmento(account)).to be_nil
    end

    it 'for_segmento e versao ainda são nil (o lote 6 preenche)' do
      expect(described_class.for_segmento('seguros/corretora')).to be_nil
      expect(described_class.versao('seguros/corretora')).to be_nil
    end
  end

  describe '.marca' do
    it 'grava segmento, versão e texto vigentes' do
      stub_bloco_atual('ATUAL')

      expect(described_class.marca(account)).to eq(
        'segmento' => 'seguros/corretora', 'versao' => 'v-ATUAL', 'texto' => 'ATUAL seguros/corretora'
      )
    end

    it 'hoje grava versão e texto nil (stubs reais)' do
      expect(described_class.marca(account)).to eq(sem_texto)
    end

    it 'é nil sem a Fase 2' do
      Autonomia::Agents::Fase2.desligar!(account)

      expect(described_class.marca(account)).to be_nil
    end
  end

  describe 'PromptBuilder' do
    it 'hoje não muda nada: o agente que nasce agora tem texto nil e o input é o de um agente sem marca' do
      com_marca = criar_agente('with_knowledge' => false, 'base' => described_class.marca(account))
      sem_marca = criar_agente('with_knowledge' => false)

      expect(input_de(com_marca)).to eq(input_de(sem_marca))
      expect(textos(input_de(com_marca))).not_to include('CONTEXTO DA CONTA')
    end

    it 'recebe o texto gravado como primeira mensagem' do
      primeira = input_de(criar_agente('with_knowledge' => false, 'base' => gravada)).first

      expect(primeira[:content].first[:text]).to start_with('CONTEXTO DA CONTA').and end_with('TEXTO GRAVADO')
    end

    it 'o texto atual do segmento mudou depois da criação: o agente continua com o texto gravado' do
      stub_bloco_atual('ANTIGO')
      agente = criar_agente('with_knowledge' => false, 'base' => described_class.marca(account))
      stub_bloco_atual('NOVO')

      texto = textos(input_de(agente.reload))
      expect(texto).to include('ANTIGO seguros/corretora')
      expect(texto).not_to include('NOVO')
    end

    it 'o agente nascido sem texto não ganha bloco depois que o conteúdo passa a existir' do
      agente = criar_agente('with_knowledge' => false, 'base' => described_class.marca(account))
      stub_bloco_atual('NOVO')

      expect(textos(input_de(agente.reload))).not_to include('NOVO')
    end

    it 'texto nil ou vazio não dá bloco' do
      stub_bloco_atual('NOVO')

      expect(textos(input_de(criar_agente('with_knowledge' => false, 'base' => sem_texto)))).not_to include('CONTEXTO DA CONTA')
      vazio = criar_agente('with_knowledge' => false, 'base' => sem_texto.merge('texto' => ''))
      expect(textos(input_de(vazio))).not_to include('CONTEXTO DA CONTA')
    end

    it 'sem marca não recebe bloco, mesmo com texto atual' do
      stub_bloco_atual('NOVO')

      expect(textos(input_de(criar_agente('with_knowledge' => false)))).not_to include('CONTEXTO DA CONTA')
    end

    it 'usa a marca, não a conta trocada para seguradora' do
      agente = criar_agente('with_knowledge' => false, 'base' => gravada)
      account.update!(internal_attributes: account.internal_attributes.to_h.merge(Autonomia::Agents::Nicho::PERFIL_KEY => 'seguradora'))
      stub_bloco_atual('NOVO')

      texto = textos(input_de(agente.reload))
      expect(texto).to include('TEXTO GRAVADO')
      expect(texto).not_to include('seguradora')
    end

    it 'sem a Fase 2, o agente marcado não recebe bloco' do
      agente = criar_agente('with_knowledge' => false, 'base' => gravada)
      Autonomia::Agents::Fase2.desligar!(account)

      expect(textos(input_de(agente.reload))).not_to include('TEXTO GRAVADO')
    end
  end

  describe 'Lia e Guia' do
    before do
      resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
      stub_bloco_atual('NOVO')
    end

    it 'a Lia nasce sem marca e, mesmo com marca forjada no banco, não recebe bloco' do
      lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call
      expect(lia.config).not_to have_key('base')

      lia.update_columns(config: lia.config.merge('base' => gravada)) # rubocop:disable Rails/SkipsModelValidations
      expect(textos(input_de(lia.reload))).not_to include('TEXTO GRAVADO')
    end

    it 'o Guia nasce sem marca e, mesmo com marca forjada, não recebe bloco' do
      Autonomia::Guide::Seed.ensure_for(account)
      guia = Autonomia::Agents::Agent.unscoped.where(account: account).find { |agente| agente.config.to_h['system_key'].present? }
      expect(guia.config).not_to have_key('base')

      guia.update_columns(config: guia.config.merge('base' => gravada)) # rubocop:disable Rails/SkipsModelValidations
      expect(textos(input_de(guia.reload))).not_to include('TEXTO GRAVADO')
    end
  end

  describe 'versões' do
    let(:user) { create(:user, account: account) }
    let(:outra) { { 'segmento' => 'seguros/seguradora', 'versao' => 'v2', 'texto' => 'OUTRO TEXTO' } }

    it 'a versão guarda a marca com o texto e voltar a ela devolve a marca inteira' do
      agente = criar_agente('with_knowledge' => false, 'base' => gravada)
      agente.record_instruction_version!(reason: 'builder_create')
      v1 = agente.instruction_versions.order(:id).last
      expect(v1.metadata['agente']['config']['base']).to eq(gravada)

      agente.update!(instruction: 'Outra instrução.', config: agente.config.merge('base' => outra))
      agente.record_instruction_version!(reason: 'builder_adjust')

      expect(agente.restore_instruction!(v1, created_by: user)).to be_truthy
      expect(agente.reload.config['base']).to eq(gravada)
      expect(agente.instruction).to eq('Atenda o cliente.')
    end

    it 'voltar a uma versão antiga, sem marca, mantém a marca atual' do
      agente = criar_agente('with_knowledge' => false)
      agente.record_instruction_version!(reason: 'builder_create')
      antiga = agente.instruction_versions.order(:id).last
      expect(antiga.metadata['agente']['config']).not_to have_key('base')

      agente.update!(instruction: 'Outra instrução.', config: agente.config.merge('base' => gravada))
      agente.restore_instruction!(antiga, created_by: user)

      expect(agente.reload.config['base']).to eq(gravada)
      expect(agente.instruction).to eq('Atenda o cliente.')
    end

    it 'o retrato aceita base ausente ou { segmento, versao, texto } com texto até 8 KB, e recusa o resto' do
      agente = criar_agente('with_knowledge' => false, 'base' => gravada)
      retrato = agente.send(:retrato_da_versao).as_json
      valido = ->(base) { Autonomia::Agents::RetratoDaVersao.valido?(retrato.merge('config' => retrato['config'].merge('base' => base))) }

      expect(Autonomia::Agents::RetratoDaVersao.valido?(retrato)).to be(true)
      expect(Autonomia::Agents::RetratoDaVersao.valido?(retrato.merge('config' => retrato['config'].except('base')))).to be(true)
      expect(valido.call(sem_texto)).to be(true)
      expect(valido.call(gravada.merge('texto' => 'a' * 8.kilobytes))).to be(true)
      expect(valido.call(gravada.merge('texto' => 'a' * (8.kilobytes + 1)))).to be(false)
      expect([gravada.merge('texto' => 1), 'seguros/corretora', { 'segmento' => 'x', 'outra' => 'y' }].map(&valido)).to all(be(false))
    end
  end
end
