require 'rails_helper'
require Rails.root.join('db/migrate/20260922200000_add_residencial_specialist_to_quote_agents.rb')

# O ENSAIO DA MIGRATION QUE LEVA O ESPECIALISTA DE RESIDENCIAL AOS AGENTES QUE JÁ EXISTEM (chat#323). O agente em
# produção nasceu antes do especialista, e o `Builder` só cria especialista no nascimento. A migration só insere:
# roda duas vezes sem duplicar, não mexe no especialista que já existe e não toca agente que não é de cotação.
RSpec.describe AddResidencialSpecialistToQuoteAgents do
  let(:account) { create(:account) }
  let(:builder) { Autonomia::Insurance::QuoteAgent::Builder }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  # O agente de antes da fase 5: nasceu só com o especialista de auto.
  def agente_antigo
    agente = builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Seguros do Vale').call
    agente.specialists.where(slug: 'cotacao_residencial').delete_all
    agente
  end

  def residencial_de(agente)
    agente.specialists.find_by(slug: 'cotacao_residencial')
  end

  it 'cria o especialista de residencial no agente que não o tem, como o Builder o criaria' do
    agente = agente_antigo

    described_class.new.up

    criado = residencial_de(agente)
    expect(criado).to have_attributes(account_id: account.id, enabled: true, name: 'Cotação residencial',
                                      tool_slugs: %w[consultar_cep cotar_seguro ver_resultado_da_cotacao])
    expect(criado.instruction).to eq(builder.instrucao_do_especialista('especialista_residencial.md'))
    expect(builder.mantido(criado)[:ramo]).to eq('residencial')
  end

  it 'roda duas vezes sem duplicar' do
    agente = agente_antigo

    2.times { described_class.new.up }

    expect(agente.specialists.where(slug: 'cotacao_residencial').count).to eq(1)
  end

  it 'não mexe no especialista que já existe' do
    agente = agente_antigo
    Autonomia::Agents::Specialist.create!(agent: agente, account: account, slug: 'cotacao_residencial', name: 'Meu',
                                          description: 'da corretora', instruction: 'Cote.', enabled: false)

    described_class.new.up

    expect(residencial_de(agente)).to have_attributes(name: 'Meu', enabled: false, instruction: 'Cote.')
  end

  it 'não toca agente que não é de cotação' do
    outro = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                             enabled: true, instruction: 'Atenda.')

    described_class.new.up

    expect(outro.specialists).to be_empty
  end
end
