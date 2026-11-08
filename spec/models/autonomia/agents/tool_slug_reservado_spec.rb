require 'rails_helper'

# #1430: a ferramenta HTTP não pode usar o nome de uma nativa. Pelo nome, a consulta dela cairia em quem lê as nativas
# pelo slug (a cotação da Lia, a medida, a memória).
RSpec.describe Autonomia::Agents::Tool do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  it 'recusa o slug de uma ferramenta nativa' do
    Autonomia::Agents::Tools::Registry.slugs.each do |slug|
      tool = described_class.new(account: account, agent: agent, name: 'X', slug: slug, endpoint_url: 'https://erp.exemplo.test/x')

      expect(tool).not_to be_valid, slug
      expect(tool.errors[:slug]).to eq([I18n.t('autonomia.agents.slug_reservado')])
    end
  end

  it 'a mensagem vem do i18n, em ingles e em portugues' do
    expect(I18n.t('autonomia.agents.slug_reservado', locale: :en)).to eq('is the name of a platform tool')
    expect(I18n.t('autonomia.agents.slug_reservado', locale: :pt_BR)).to eq('é o nome de uma ferramenta da plataforma')
  end

  it 'aceita um slug que nenhuma nativa usa' do
    tool = described_class.new(account: account, agent: agent, name: 'X', slug: 'consultar_pedido', endpoint_url: 'https://erp.exemplo.test/x')

    expect(tool).to be_valid
  end

  it 'so confere o slug quando ele muda: a ferramenta antiga com nome hoje reservado continua editavel' do
    tool = described_class.create!(account: account, agent: agent, name: 'X', slug: 'consultar_pedido', endpoint_url: 'https://erp.exemplo.test/x')
    tool.update_column(:slug, Autonomia::Agents::Tools::Registry.slugs.first) # rubocop:disable Rails/SkipsModelValidations

    expect(tool.reload.update(name: 'Outro nome')).to be(true)
    expect(tool.update(slug: Autonomia::Agents::Tools::Registry.slugs.last)).to be(false)
  end
end
