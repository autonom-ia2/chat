require 'rails_helper'

RSpec.describe 'Super Admin agents niche', type: :request do
  let(:account) { create(:account, internal_attributes: { 'unrelated' => 'preserved', 'autonomia_insurance_enabled' => true }) }
  let(:path) { "/super_admin/accounts/#{account.id}" }
  let(:nicho_key) { Autonomia::Agents::Nicho::NICHO_KEY }
  let(:perfil_key) { Autonomia::Agents::Nicho::PERFIL_KEY }

  around do |example|
    GlobalConfig.clear_cache(Autonomia::Agents::Nicho::PADRAO_KEY)
    example.run
    GlobalConfig.clear_cache(Autonomia::Agents::Nicho::PADRAO_KEY)
  end

  before { sign_in(create(:super_admin), scope: :super_admin) }

  def radios(document, campo)
    document.css(%(input[type="radio"][name="account[agents_niche][#{campo}]"]))
  end

  it 'mostra o nicho em cartões, sem select, com o padrão da instalação e o aviso' do
    with_modified_env(AUTONOMIA_NICHO_PADRAO: 'seguros:corretora') { get "#{path}/edit" }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    campo = document.at_css('[data-agents-niche-form]')
    expect(radios(document, 'nicho').pluck('value')).to eq(%w[seguros geral])
    expect(radios(document, 'perfil').pluck('value')).to eq(%w[corretora seguradora insurtech])
    expect(radios(document, 'nicho').find { |radio| radio['checked'] }['value']).to eq('seguros')
    expect(campo.css('select')).to be_empty
    expect(campo.text.squish).to include('Default for this installation: Insurance · Broker')
    expect(campo.text.squish).to include(
      'Changing the niche does not change agents that already exist; they only change through the Update with the new base button.'
    )
  end

  it 'liga cada cartão ao seu rótulo, com alvo de toque de 44 px' do
    get "#{path}/edit"

    document = Nokogiri::HTML(response.body)
    (radios(document, 'nicho') + radios(document, 'perfil')).each do |radio|
      label = radio.ancestors('label').first
      expect(label).to be_present
      expect(label['class'].split).to include('min-h-11')
    end
  end

  it 'não deixa rótulo apontando para um campo que não existe' do
    get "#{path}/edit"

    document = Nokogiri::HTML(response.body)
    expect(document.css('label[for="account_agents_niche"]')).to be_empty
    expect(document.at_css('[data-agents-niche-form] legend').text.squish).to eq('AI agents niche')
  end

  it 'mostra o nicho efetivo na página da conta' do
    account.update!(internal_attributes: account.internal_attributes.merge(nicho_key => 'seguros', perfil_key => 'insurtech'))

    get path

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('[data-agents-niche]').text.squish).to eq('Insurance · Insurtech')
  end

  it 'grava nicho e perfil no update sem apagar as outras chaves de internal_attributes' do
    patch path, params: { account: { name: account.name, agents_niche: { nicho: 'seguros', perfil: 'insurtech' } } }

    expect(response).to have_http_status(:redirect)
    expect(account.reload.internal_attributes).to eq(
      'unrelated' => 'preserved', 'autonomia_insurance_enabled' => true, nicho_key => 'seguros', perfil_key => 'insurtech'
    )
  end

  it 'troca para geral e tira o perfil, mantendo as outras chaves' do
    account.update!(internal_attributes: account.internal_attributes.merge(nicho_key => 'seguros', perfil_key => 'seguradora'))

    patch path, params: { account: { name: account.name, agents_niche: { nicho: 'geral', perfil: 'seguradora' } } }

    expect(response).to have_http_status(:redirect)
    expect(account.reload.internal_attributes).to eq('unrelated' => 'preserved', 'autonomia_insurance_enabled' => true, nicho_key => 'geral')
  end

  it 'não grava nicho fora da lista' do
    patch path, params: { account: { name: account.name, agents_niche: { nicho: 'saude' } } }

    expect(account.reload.internal_attributes).to eq('unrelated' => 'preserved', 'autonomia_insurance_enabled' => true)
  end

  it 'mantém a escolha numa edição que não manda o campo' do
    account.update!(internal_attributes: account.internal_attributes.merge(nicho_key => 'geral'))

    patch path, params: { account: { name: 'Renamed account' } }

    expect(account.reload.internal_attributes[nicho_key]).to eq('geral')
  end
end
