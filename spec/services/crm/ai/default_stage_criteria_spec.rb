require 'rails_helper'

RSpec.describe Crm::Ai::DefaultStageCriteria do
  it 'returns criteria for default stage names' do
    expect(described_class.criteria_for('Novo')).to include('Primeiro contato')
    expect(described_class.criteria_for('Perdido')).to include('sem conversão')
  end

  it 'builds metadata for known stages' do
    expect(described_class.metadata_for('Proposta')).to eq(
      'ai_criteria' => described_class.criteria_for('Proposta')
    )
  end

  it 'knows the stages of the ready-made Sales pipeline, in plain words' do
    names = ['Novo contato', 'Em conversa', 'Proposta enviada', 'Negociação', 'Fechado']

    expect(names.map { |name| described_class.criteria_for(name) }).to all(be_present)
    expect(described_class.criteria_for('  NEGOCIAÇÃO ')).to include('acertando detalhes')
  end

  it 'knows the stages of the ready-made Service and Appointments pipelines' do
    names = ['Novo pedido', 'Em atendimento', 'Esperando o cliente', 'Resolvido',
             'Novo contato', 'Horário marcado', 'Atendido', 'Não veio']

    expect(names.map { |name| described_class.criteria_for(name) }).to all(be_present)
  end

  # #1498
  it 'knows the stages of the After-sales, Collections and Appointment templates only in a Serve pipeline' do
    names = ['Compra feita', 'Acompanhando', 'Tudo certo', 'A vencer', 'Atrasado', 'Prometeu pagar', 'Pago',
             'Pediu horário', 'Precisa remarcar']

    expect(names.map { |name| described_class.criteria_for(name, atender: true) }).to all(be_present)
    expect(names.map { |name| described_class.criteria_for(name) }).to all(be_nil)
  end

  it 'reads "Em atendimento" as service in a Serve pipeline and keeps the sale meaning otherwise' do
    expect(described_class.criteria_for('Em atendimento', atender: true)).to include('cuidando do pedido')
    expect(described_class.criteria_for('Em atendimento')).to include('proposta')
    expect(described_class.metadata_for('Novo', atender: true)['ai_criteria']).to include('pedir ajuda')
  end
end
