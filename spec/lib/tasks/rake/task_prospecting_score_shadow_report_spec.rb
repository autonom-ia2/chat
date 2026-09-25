require 'rake'
require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['prospecting:score_shadow_report'] }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    Rails.application.load_tasks unless described_class.task_defined?('prospecting:score_shadow_report')
    task.reenable
  end

  it 'imprime a comparação da conta no período pedido' do
    lead = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/a', name: 'Padaria Alfa')
    orth = { 'score' => 80, 'priority_score' => 90, 'band' => 'very_hot', 'human_insight' => 'Oportunidade alta: sem site.' }
    Autonomia::Prospecting::Search.create!(
      account: account, user: user, query: 'padaria', provider: 'mock', status: :completed,
      metadata: { 'lead_scoring' => { lead.id.to_s => { 'score' => 20.0, 'priority_score' => 10.0, 'orth' => orth } } }
    )

    expect { task.invoke(account.id.to_s, '7') }.to output(
      a_string_including("Conta #{account.id}, últimos 7 dias", 'Buscas comparadas: 1 (sem nota sombra: 0)',
                         'Leads: 1. Sobem: 1. Descem: 0. Iguais: 0.',
                         "1. Padaria Alfa (lead #{lead.id}): prioridade 10 -> 90, Prioridade baixa -> Lead muito quente. " \
                         'Oportunidade alta: sem site.')
    ).to_stdout
  end

  it 'recusa conta inexistente' do
    expect { task.invoke('0', '7') }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
