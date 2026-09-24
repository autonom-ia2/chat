require 'rails_helper'
require Rails.root.join('db/migrate/20260924150000_add_empresarial_specialist_to_quote_agents.rb')

# O ENSAIO DA MIGRATION QUE LEVA O ESPECIALISTA DE EMPRESARIAL AOS AGENTES QUE JÁ EXISTEM (chat#641). O agente em
# produção nasceu antes do especialista, e o `Builder` só cria especialista no nascimento. A migration só insere:
# roda duas vezes sem duplicar, não mexe no especialista que já existe e não toca agente que não é de cotação.
RSpec.describe AddEmpresarialSpecialistToQuoteAgents do
  let(:account) { create(:account) }
  let(:builder) { Autonomia::Insurance::QuoteAgent::Builder }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  # O agente de antes da chat#641: nasceu sem o especialista de empresarial.
  def agente_antigo
    agente = builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Seguros do Vale').call
    agente.specialists.where(slug: 'cotacao_empresarial').delete_all
    agente
  end

  def empresarial_de(agente)
    agente.specialists.find_by(slug: 'cotacao_empresarial')
  end

  it 'cria o especialista de empresarial no agente que não o tem, como o Builder o criaria' do
    agente = agente_antigo

    described_class.new.up

    criado = empresarial_de(agente)
    expect(criado).to have_attributes(account_id: account.id, enabled: true, name: 'Cotação empresarial',
                                      tool_slugs: %w[consultar_cep buscar_atividade cotar_seguro ver_resultado_da_cotacao])
    expect(criado.instruction).to eq(builder.instrucao_do_especialista('especialista_empresarial.md'))
    expect(builder.mantido(criado)[:ramo]).to eq('empresarial')
  end

  it 'roda duas vezes sem duplicar' do
    agente = agente_antigo

    2.times { described_class.new.up }

    expect(agente.specialists.where(slug: 'cotacao_empresarial').count).to eq(1)
  end

  it 'não mexe no especialista que já existe' do
    agente = agente_antigo
    Autonomia::Agents::Specialist.create!(agent: agente, account: account, slug: 'cotacao_empresarial', name: 'Meu',
                                          description: 'da corretora', instruction: 'Cote.', enabled: false)

    described_class.new.up

    expect(empresarial_de(agente)).to have_attributes(name: 'Meu', enabled: false, instruction: 'Cote.')
  end

  it 'não toca agente que não é de cotação' do
    outro = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                             enabled: true, instruction: 'Atenda.')

    described_class.new.up

    expect(outro.specialists).to be_empty
  end
end
