require 'rails_helper'

RSpec.describe 'Autonomia::Agents::MirrorIdentitySync' do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:service_class) { Autonomia::Agents::MirrorIdentitySync }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agente original', agent_type: 'custom',
                                     mode: :guided, status: :active, enabled: true,
                                     actuation: :external, instruction: 'Atenda.')
  end

  def create_link(owner:, name:, outgoing_url: nil, archived: false)
    inbox = create(:inbox, account: owner.account, name: name)
    mirror = AgentBot.create!(account: owner.account, name: "Espelho #{name}", bot_type: :webhook,
                              outgoing_url: outgoing_url)
    link = Autonomia::Agents::AgentInbox.create!(agent: owner, inbox: inbox, account: owner.account,
                                                 agent_bot: mirror)
    AgentBotInbox.create!(inbox: inbox, agent_bot: mirror, account: owner.account) unless archived
    link.update!(deleted_at: Time.current, updated_at: Time.current) if archived
    [link, mirror]
  end

  it 'syncs the name to every kept native mirror and leaves other identities untouched' do
    _, first_mirror = create_link(owner: agent, name: 'Primeira caixa')
    _, second_mirror = create_link(owner: agent, name: 'Segunda caixa')
    _, archived_mirror = create_link(owner: agent, name: 'Caixa arquivada', archived: true)
    _, external_mirror = create_link(owner: agent, name: 'Bot externo', outgoing_url: 'https://bot.example')
    foreign_agent = Autonomia::Agents::Agent.create!(account: other_account, name: 'Outro agente', agent_type: 'custom')
    _, foreign_mirror = create_link(owner: foreign_agent, name: 'Outra conta')

    agent.update!(name: 'Agente renomeado')
    service_class.new(agent: agent).perform

    expect(first_mirror.reload.name).to eq('Agente renomeado')
    expect(second_mirror.reload.name).to eq('Agente renomeado')
    expect(archived_mirror.reload.name).to eq('Espelho Caixa arquivada')
    expect(external_mirror.reload.name).to eq('Espelho Bot externo')
    expect(foreign_mirror.reload.name).to eq('Espelho Outra conta')
  end

  it 'copies and removes the same avatar blob on kept native mirrors' do
    _, first_mirror = create_link(owner: agent, name: 'Primeira caixa')
    _, second_mirror = create_link(owner: agent, name: 'Segunda caixa')
    _, archived_mirror = create_link(owner: agent, name: 'Caixa arquivada', archived: true)
    avatar = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')

    agent.avatar.attach(avatar)
    service_class.new(agent: agent).perform

    expect(first_mirror.reload.avatar.blob_id).to eq(agent.avatar.blob_id)
    expect(second_mirror.reload.avatar.blob_id).to eq(agent.avatar.blob_id)
    expect(archived_mirror.reload.avatar).not_to be_attached

    agent.avatar.purge
    service_class.new(agent: agent).perform

    expect(first_mirror.reload.avatar).not_to be_attached
    expect(second_mirror.reload.avatar).not_to be_attached
    expect(archived_mirror.reload.avatar).not_to be_attached
  end

  it 'preserves the private test namespace when only the avatar changes' do
    private_state = {
      '_autonomia_agents_redesign' => {
        'version' => 1,
        'test' => {
          'completion' => 'completed',
          'tested_digest' => 'sha256:old',
          'material_snapshot_digest' => 'sha256:material'
        },
        'test_invalidated_by' => nil
      }
    }
    agent.update!(config: agent.config.merge(private_state))
    create_link(owner: agent, name: 'Primeira caixa')
    agent.avatar.attach(fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))

    service_class.new(agent: agent).perform

    expect(agent.reload.config.fetch('_autonomia_agents_redesign')).to eq(private_state['_autonomia_agents_redesign'])
  end
end
