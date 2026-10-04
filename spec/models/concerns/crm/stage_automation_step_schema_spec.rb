require 'rails_helper'

RSpec.describe Crm::StageAutomationStepSchema do
  let(:conta) { create(:account) }

  def erros(tipo, config)
    passo = Crm::StageAutomationStep.new(account: conta, action_type: tipo, action_config: config)
    passo.validate
    (passo.errors.full_messages - ['Stage automation must exist']).join(' | ')
  end

  # AC-G3: todo action_type tem ramo, e todo ramo o executor roda (o do Decisor roda na sequência).
  it 'tem um ramo por action_type, e cada um tem quem execute', :aggregate_failures do
    expect(described_class.por_tipo.keys).to match_array(Crm::StageAutomationStep.action_types.keys)
    described_class.por_tipo.each_key do |tipo|
      executa = Crm::StageAutomations::StepExecutor.private_method_defined?("#{tipo}!") || tipo == Autonomia::Decisores::PASSO
      expect(executa).to be(true), "#{tipo} não tem execução"
    end
  end

  it 'sem passo, o esquema traz todos os tipos, cada um com x-quando' do
    expect(described_class.action_config['anyOf'].map { |ramo| ramo.dig('x-quando', 'action_type') })
      .to match_array(Crm::StageAutomationStep.action_types.keys)
  end

  it 'aceita os três tipos de passo como o executor lê', :aggregate_failures do
    expect(erros('create_follow_up', { title: 'Ligar', follow_up_type: 'call' })).to eq('')
    expect(erros('create_follow_up', { title: 'Oi', automation_mode: 'auto_send_message', metadata: { message_body: 'Oi' } })).to eq('')
    expect(erros('assign_owner', { owner_id: 7 })).to eq('')
    expect(erros('assign_owner', { owner_id: '', use_card_owner: true })).to eq('')
    expect(erros('move_stage', { target_stage_id: 11 })).to eq('')
  end

  # AC-G8: a chave que o executor não lê gravava em silêncio.
  it 'recusa chave que o executor não lê e o que falta', :aggregate_failures do
    expect(erros('create_follow_up', { titulo: 'x' })).to include('Titulo is not allowed', 'Title is required')
    expect(erros('assign_owner', {})).to include('Owner is required', 'Use card owner is required')
    expect(erros('move_stage', { target_stage_id: '' })).to include('too short')
    expect(erros('create_follow_up', { title: 'x', follow_up_type: 'visita' })).to include('"visita" is not one of')
  end

  it 'o passo do Decisor exige decisor_id e chave_que_segue' do
    expect(erros(Autonomia::Decisores::PASSO, {})).to include('Decisor is required', 'Chave que segue is required')
  end
end
