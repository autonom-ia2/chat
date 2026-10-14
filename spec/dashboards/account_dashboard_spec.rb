require 'rails_helper'

RSpec.describe AccountDashboard do
  # As listas do dashboard são montadas ao carregar a classe. Para ver os dois ramos, o arquivo é avaliado de novo
  # dentro de um módulo anônimo, com ChatwootApp.enterprise? simulado, sem redefinir o AccountDashboard de verdade.
  def dashboard_com(enterprise:)
    allow(ChatwootApp).to receive_messages(enterprise?: enterprise, chatwoot_cloud?: false)
    Module.new.tap { |escopo| escopo.module_eval(Rails.root.join('app/dashboards/account_dashboard.rb').read) }::AccountDashboard
  end

  [true, false].each do |enterprise|
    it "mostra e edita o nicho dos agentes com enterprise?=#{enterprise}" do
      dashboard = dashboard_com(enterprise: enterprise)

      expect(dashboard::ATTRIBUTE_TYPES[:agents_niche]).to eq(AgentsNicheField)
      expect(dashboard::SHOW_PAGE_ATTRIBUTES).to include(:agents_niche)
      expect(dashboard::FORM_ATTRIBUTES).to include(:agents_niche)
      expect(dashboard::FORM_ATTRIBUTES.include?(:feature_instagram_assisted_onboarding)).to be(!enterprise)
    end
  end
end
