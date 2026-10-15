require 'rails_helper'

# #1568: o calendário do CRM usa o fuso da plataforma quando a conta não tem fuso, nunca o do navegador.
describe 'Fuso padrão do CRM na tela', type: :request do
  it 'expõe o fuso que o CRM usa quando a conta não tem fuso' do
    with_modified_env CRM_DEFAULT_TIMEZONE: 'America/Cuiaba' do
      get '/app/login'
    end

    expect(response.body).to include('"CRM_DEFAULT_TIMEZONE":"America/Cuiaba"')
  end

  it 'cai no padrão do CRM quando o ambiente não define' do
    with_modified_env CRM_DEFAULT_TIMEZONE: nil do
      get '/app/login'
    end

    expect(response.body).to include(%("CRM_DEFAULT_TIMEZONE":"#{Crm::Timezone::Resolver::FALLBACK_TIMEZONE}"))
  end
end
