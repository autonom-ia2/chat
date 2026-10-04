require 'rails_helper'

# AC-I2 (#935): quantas vezes a regra disparou, por hora, no Redis e no JSON da regra.
RSpec.describe AutomationRules::Disparos, type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:rule) do
    create(:automation_rule, account: account, actions: [{ action_name: 'add_label', action_params: ['vip'] }])
  end

  before { Redis::Alfred.scan_each(match: 'automation_rule:disparos:*') { |chave| Redis::Alfred.delete(chave) } }

  it 'conta cada disparo da regra e mostra no JSON dela', :aggregate_failures do
    5.times { AutomationRules::ActionService.new(rule, account, conversation).perform }

    get "/api/v1/accounts/#{account.id}/automation_rules/#{rule.id}", headers: administrator.create_new_auth_token

    expect(response.parsed_body.dig('payload', 'disparos')).to eq('hora' => 5, 'ultimas_24h' => 5)
  end

  it 'retomar depois do Decisor não conta como disparo novo' do
    AutomationRules::ActionService.new(rule, account, conversation).perform(desde: 1)

    expect(described_class.de(rule.id)).to eq(hora: 0, ultimas_24h: 0)
  end

  it 'soma as últimas 24 horas, e a hora é só a atual', :aggregate_failures do
    travel_to(Time.zone.parse('2026-10-04 10:15')) { 2.times { described_class.registrar(rule.id) } }
    travel_to(Time.zone.parse('2026-10-04 12:05')) do
      described_class.registrar(rule.id)

      expect(described_class.de(rule.id)).to eq(hora: 1, ultimas_24h: 3)
    end
  end

  it 'o contador vence em até 48 h e guarda só número', :aggregate_failures do
    described_class.registrar(rule.id)
    chave = described_class.chave(rule.id, Time.current)

    expect(Redis::Alfred.ttl(chave)).to be_between(1, 48.hours.to_i)
    expect(Redis::Alfred.get(chave)).to eq('1')
  end
end
