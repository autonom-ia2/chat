require 'rails_helper'

# MARCA DE BASE (#1429): o agente guarda em `config['base']` o segmento com que nasceu e lê o bloco por ela, nunca pela
# conta. Trocar o tipo da conta (ou o lote 6 dar texto ao bloco) não muda agente existente.
RSpec.describe Autonomia::Agents::PromptParts::SegmentoDoAgente do
  let(:account) { conta_da_fase2 }
  let(:corretora) { { 'segmento' => 'seguros/corretora', 'versao' => nil } }
  let(:corretora_v1) { { 'segmento' => 'seguros/corretora', 'versao' => 'aaaabbbbcccc' } }
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

  def stub_bloco_por_segmento
    allow(Autonomia::Segmentos::Bloco).to receive(:for_segmento) { |seg| seg && "BLOCO #{seg}" }
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

  describe 'PromptBuilder' do
    it 'hoje não muda nada: com marca e Fase 2, o bloco real é nil e o input é o de um agente sem marca' do
      com_marca = criar_agente('with_knowledge' => false, 'base' => corretora_v1)
      sem_marca = criar_agente('with_knowledge' => false)

      expect(input_de(com_marca)).to eq(input_de(sem_marca))
      expect(textos(input_de(com_marca))).not_to include('CONTEXTO DA CONTA')
    end

    it 'agente sem marca não recebe bloco, mesmo se for_segmento devolver texto' do
      stub_bloco_por_segmento

      expect(textos(input_de(criar_agente('with_knowledge' => false)))).not_to include('BLOCO')
    end

    it 'com a sonda ligada, o agente marcado recebe o bloco da marca como primeira mensagem' do
      stub_bloco_por_segmento

      primeira = input_de(criar_agente('with_knowledge' => false, 'base' => corretora_v1)).first
      expect(primeira[:content].first[:text]).to start_with('CONTEXTO DA CONTA').and end_with('BLOCO seguros/corretora')
    end

    it 'usa a marca (corretora), não a conta trocada para seguradora' do
      agente = criar_agente('with_knowledge' => false, 'base' => corretora_v1)
      account.update!(internal_attributes: account.internal_attributes.to_h.merge(Autonomia::Agents::Nicho::PERFIL_KEY => 'seguradora'))
      stub_bloco_por_segmento

      texto = textos(input_de(agente.reload))
      expect(texto).to include('BLOCO seguros/corretora')
      expect(texto).not_to include('seguradora')
    end

    it 'marca com versao nil não recebe bloco, mesmo se for_segmento devolver texto' do
      stub_bloco_por_segmento

      expect(textos(input_de(criar_agente('with_knowledge' => false, 'base' => corretora)))).not_to include('BLOCO')
    end

    it 'o agente nascido com versao nil não ganha bloco depois que o conteúdo passa a existir' do
      marca = described_class.marca(account)
      expect(marca).to eq(corretora)
      agente = criar_agente('with_knowledge' => false, 'base' => marca)

      stub_bloco_por_segmento
      allow(Autonomia::Segmentos::Bloco).to receive(:versao).and_return('aaaabbbbcccc')

      expect(textos(input_de(agente.reload))).not_to include('BLOCO')
      expect(described_class.marca(account)).to eq(corretora_v1)
    end

    it 'sem a Fase 2, o agente marcado não recebe bloco' do
      agente = criar_agente('with_knowledge' => false, 'base' => corretora_v1)
      Autonomia::Agents::Fase2.desligar!(account)
      stub_bloco_por_segmento

      expect(textos(input_de(agente.reload))).not_to include('BLOCO')
    end
  end

  describe 'Lia e Guia' do
    before do
      resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
      stub_bloco_por_segmento
    end

    it 'a Lia nasce sem marca e não recebe bloco' do
      lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call

      expect(lia.config).not_to have_key('base')
      expect(textos(input_de(lia))).not_to include('BLOCO')
    end

    it 'a Lia, mesmo com uma marca forjada no banco, não recebe bloco' do
      lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call
      lia.update_columns(config: lia.config.merge('base' => corretora_v1)) # rubocop:disable Rails/SkipsModelValidations

      expect(textos(input_de(lia.reload))).not_to include('BLOCO')
    end

    it 'o Guia nasce sem marca e não recebe bloco, mesmo com marca forjada' do
      Autonomia::Guide::Seed.ensure_for(account)
      guia = Autonomia::Agents::Agent.unscoped.where(account: account).find { |agente| agente.config.to_h['system_key'].present? }

      expect(guia.config).not_to have_key('base')
      guia.update_columns(config: guia.config.merge('base' => corretora_v1)) # rubocop:disable Rails/SkipsModelValidations
      expect(textos(input_de(guia.reload))).not_to include('BLOCO')
    end
  end

  describe 'versões' do
    let(:user) { create(:user, account: account) }
    let(:seguradora) { { 'segmento' => 'seguros/seguradora', 'versao' => 'abc123def456' } }

    it 'a versão guarda a marca e voltar a ela devolve a marca' do
      agente = criar_agente('with_knowledge' => false, 'base' => corretora)
      agente.record_instruction_version!(reason: 'builder_create')
      v1 = agente.instruction_versions.order(:id).last
      expect(v1.metadata['agente']['config']['base']).to eq(corretora)

      agente.update!(instruction: 'Outra instrução.', config: agente.config.merge('base' => seguradora))
      agente.record_instruction_version!(reason: 'builder_adjust')

      expect(agente.restore_instruction!(v1, created_by: user)).to be_truthy
      expect(agente.reload.config['base']).to eq(corretora)
      expect(agente.instruction).to eq('Atenda o cliente.')
    end

    it 'voltar a uma versão antiga, sem marca, mantém a marca atual' do
      agente = criar_agente('with_knowledge' => false)
      agente.record_instruction_version!(reason: 'builder_create')
      antiga = agente.instruction_versions.order(:id).last
      expect(antiga.metadata['agente']['config']).not_to have_key('base')

      agente.update!(instruction: 'Outra instrução.', config: agente.config.merge('base' => corretora))
      agente.restore_instruction!(antiga, created_by: user)

      expect(agente.reload.config['base']).to eq(corretora)
      expect(agente.instruction).to eq('Atenda o cliente.')
    end

    it 'o retrato aceita base ausente ou { segmento, versao } com texto ou nil, e recusa o resto' do
      agente = criar_agente('with_knowledge' => false, 'base' => corretora)
      retrato = agente.send(:retrato_da_versao).as_json
      valido = ->(base) { Autonomia::Agents::RetratoDaVersao.valido?(retrato.merge('config' => retrato['config'].merge('base' => base))) }

      expect(Autonomia::Agents::RetratoDaVersao.valido?(retrato)).to be(true)
      expect(Autonomia::Agents::RetratoDaVersao.valido?(retrato.merge('config' => retrato['config'].except('base')))).to be(true)
      expect(valido.call(seguradora)).to be(true)
      expect(valido.call('seguros/corretora')).to be(false)
      expect(valido.call({ 'segmento' => 1 })).to be(false)
      expect(valido.call({ 'segmento' => 'x', 'outra' => 'y' })).to be(false)
    end
  end
end
