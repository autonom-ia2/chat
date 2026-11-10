require 'rails_helper'

RSpec.describe Crm::Activity, '.actor_type_for' do
  it 'sem ator, é o sistema' do
    expect(described_class.actor_type_for(nil)).to eq('system')
  end

  it 'agente comum é user' do
    expect(described_class.actor_type_for(build(:user))).to eq('user')
  end

  it 'super admin, subclasse de User, também é user' do
    expect(described_class.actor_type_for(build(:super_admin))).to eq('user')
  end
end
