require 'rails_helper'

RSpec.describe Autonomia::Agents::PromptBuilder, type: :service do
  let(:account) { create(:account) }

  def prompt_for(agent, surface: :live)
    described_class.new(agent: agent, query: 'oi', surface: surface).instructions
  end

  def new_agent(name: 'Clara', config: {}, **attributes)
    Autonomia::Agents::Agent.new(
      account: account,
      name: name,
      agent_type: 'custom',
      actuation: :external,
      instruction: 'Atenda com clareza.',
      config: config,
      **attributes
    )
  end

  describe 'handoff_strategy (BE-12)' do
    it 'não altera bytes para nil, low_confidence, none ou valor desconhecido' do
      baseline = prompt_for(new_agent)

      %w[low_confidence none valor_novo].each do |strategy|
        configured = prompt_for(new_agent(config: { 'handoff_strategy' => strategy }))
        expect(configured).to eq(baseline), "estratégia #{strategy.inspect} não deveria mudar o prompt"
      end
    end

    it 'coloca a regra textual de sempre oferecer no atendimento externo' do
      prompt = prompt_for(new_agent(config: { 'handoff_strategy' => 'always_ask' }))

      expect(prompt).not_to eq(prompt_for(new_agent))
      expect(prompt).to include('falar com uma pessoa')
    end

    it 'aplica a mesma regra de sempre oferecer ao agente manual externo' do
      prompt = prompt_for(new_agent(mode: :manual, config: { 'handoff_strategy' => 'always_ask' }))

      expect(prompt).to include('falar com uma pessoa')
    end

    it 'coloca a regra textual de nunca oferecer por iniciativa própria' do
      prompt = prompt_for(new_agent(config: { 'handoff_strategy' => 'never' }))

      expect(prompt).not_to eq(prompt_for(new_agent))
      expect(prompt).to include('somente quando a pessoa pedir')
    end

    it 'aplica a regra de nunca oferecer por iniciativa própria ao agente manual externo' do
      prompt = prompt_for(new_agent(mode: :manual, config: { 'handoff_strategy' => 'never' }))

      expect(prompt).to include('somente quando a pessoa pedir')
    end

    it 'não coloca a estratégia no Copilot, mesmo quando o agente é both' do
      baseline = new_agent(actuation: :both)
      configured = new_agent(actuation: :both, config: { 'handoff_strategy' => 'always_ask' })

      expect(prompt_for(configured, surface: :copilot)).to eq(prompt_for(baseline, surface: :copilot))
    end
  end

  describe 'nome após a instrução guiada (BE-29)' do
    it 'acrescenta a identidade só quando o nome mudou depois da geração' do
      agent = new_agent
      agent.save!
      Autonomia::Agents::InstructionVersion.create!(
        agent: agent,
        account: account,
        instruction: agent.instruction,
        instruction_hash: Digest::SHA256.hexdigest(agent.instruction),
        reason: 'builder',
        metadata: { 'origin' => 'guided', 'agent_name' => 'Clara' }
      )
      agent.update!(name: 'Bia')

      expect(prompt_for(agent)).to include('Seu nome é Bia.')
    end

    it 'acrescenta a identidade ao ajudante interno guiado' do
      agent = new_agent(name: 'Clara', actuation: :internal)
      agent.save!
      Autonomia::Agents::InstructionVersion.create!(
        agent: agent,
        account: account,
        instruction: agent.instruction,
        instruction_hash: Digest::SHA256.hexdigest(agent.instruction),
        reason: 'builder',
        metadata: { 'origin' => 'guided', 'agent_name' => 'Clara' }
      )
      agent.update!(name: 'Bia')

      expect(prompt_for(agent, surface: :copilot)).to include('Seu nome é Bia.')
    end

    it 'acrescenta a identidade nas duas pernas de um agente both' do
      agent = new_agent(name: 'Clara', actuation: :both)
      agent.save!
      Autonomia::Agents::InstructionVersion.create!(
        agent: agent,
        account: account,
        instruction: agent.instruction,
        instruction_hash: Digest::SHA256.hexdigest(agent.instruction),
        reason: 'builder',
        metadata: { 'origin' => 'guided', 'agent_name' => 'Clara' }
      )
      agent.update!(name: 'Bia')

      expect(prompt_for(agent)).to include('Seu nome é Bia.')
      expect(prompt_for(agent, surface: :copilot)).to include('Seu nome é Bia.')
    end

    it 'mantém bytes quando a versão guiada já usava o nome atual' do
      agent = new_agent
      agent.save!
      Autonomia::Agents::InstructionVersion.create!(
        agent: agent,
        account: account,
        instruction: agent.instruction,
        instruction_hash: Digest::SHA256.hexdigest(agent.instruction),
        reason: 'builder',
        metadata: { 'origin' => 'guided', 'agent_name' => 'Clara' }
      )

      expect(prompt_for(agent)).not_to include('Seu nome é Clara.')
    end

    it 'não infere identidade de versões antigas sem o metadado do nome' do
      agent = new_agent
      agent.save!
      Autonomia::Agents::InstructionVersion.create!(
        agent: agent,
        account: account,
        instruction: agent.instruction,
        instruction_hash: Digest::SHA256.hexdigest(agent.instruction),
        reason: 'builder',
        metadata: {}
      )
      agent.update!(name: 'Bia')

      expect(prompt_for(agent)).not_to include('Seu nome é Bia.')
    end

    it 'não reescreve o texto manual, a Lia ou o Guia' do
      manual = new_agent(name: 'Bia', mode: :manual)
      quote = new_agent(name: 'Bia')
      allow(quote).to receive(:agent_type).and_return('insurance_quote')
      allow(quote).to receive(:instrucao_do_sistema).and_return('Instrução mantida da Lia')
      guide = new_agent(name: 'Bia', config: { 'system_key' => 'guide' })

      [
        [manual, :live], [quote, :live], [guide, :live]
      ].each do |agent, surface|
        expect(prompt_for(agent, surface: surface)).not_to include('Seu nome é Bia.')
      end
    end
  end

  describe 'greeting e fallback externos (BE-30)' do
    it 'altera o prompt externo guiado quando os dois campos estão preenchidos' do
      baseline = prompt_for(new_agent)
      configured = new_agent(greeting: 'Olá, sou a Clara.', fallback_message: 'Vou chamar uma pessoa da equipe.')

      prompt = prompt_for(configured)
      expect(prompt).not_to eq(baseline)
      expect(prompt).to include('Olá, sou a Clara.', 'Vou chamar uma pessoa da equipe.')
    end

    it 'altera o prompt externo manual quando os dois campos estão preenchidos' do
      baseline = prompt_for(new_agent(mode: :manual))
      configured = new_agent(
        mode: :manual,
        greeting: 'Olá, sou a Clara.',
        fallback_message: 'Vou chamar uma pessoa da equipe.'
      )

      prompt = prompt_for(configured)
      expect(prompt).not_to eq(baseline)
      expect(prompt).to include('Olá, sou a Clara.', 'Vou chamar uma pessoa da equipe.')
    end

    it 'mantém bytes do interno, Copilot, Lia e Guia apesar dos campos externos' do
      quote_base = new_agent(greeting: 'Olá, pessoa.', fallback_message: 'A equipe vai ajudar.')
      allow(quote_base).to receive(:agent_type).and_return('insurance_quote')
      allow(quote_base).to receive(:instrucao_do_sistema).and_return('Instrução mantida')
      quote_configured = quote_base.dup
      allow(quote_configured).to receive(:agent_type).and_return('insurance_quote')
      allow(quote_configured).to receive(:instrucao_do_sistema).and_return('Instrução mantida')

      variants = [
        [:copilot, new_agent(actuation: :internal, greeting: 'Olá, pessoa.', fallback_message: 'A equipe vai ajudar.')],
        [:copilot, new_agent(actuation: :both, greeting: 'Olá, pessoa.', fallback_message: 'A equipe vai ajudar.')],
        [:live, quote_base, quote_configured],
        [:guide, new_agent(
          config: { 'system_key' => 'guide' },
          greeting: 'Olá, pessoa.',
          fallback_message: 'A equipe vai ajudar.'
        )]
      ]

      variants.each do |surface, base, provided_configured|
        configured = provided_configured || base.dup
        configured.config = base.config.merge('handoff_strategy' => 'always_ask')

        expect(prompt_for(configured, surface: surface)).to eq(prompt_for(base, surface: surface))
      end
    end
  end
end
