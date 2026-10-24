require 'rails_helper'

RSpec.describe 'Super Admin agents niche', type: :request do
  let(:account) { create(:account, internal_attributes: { 'unrelated' => 'preserved', 'autonomia_insurance_enabled' => true }) }
  let(:path) { "/super_admin/accounts/#{account.id}" }
  let(:nicho_key) { Autonomia::Agents::Nicho::NICHO_KEY }
  let(:perfil_key) { Autonomia::Agents::Nicho::PERFIL_KEY }
  let(:canal_key) { Autonomia::Agents::Nicho::CANAL_KEY }

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
    expect(radios(document, 'nicho').pluck('value')).to eq(%w[geral seguros])
    expect(radios(document, 'perfil').pluck('value')).to eq(%w[corretora seguradora insurtech saude_beneficios])
    expect(radios(document, 'nicho').find { |radio| radio['checked'] }['value']).to eq('seguros')
    expect(campo.css('select')).to be_empty
    expect(campo.text.squish).to include('Default for this installation: Insurance · Broker')
    expect(campo.text.squish).to include(
      'The change shows the next time the team opens the dashboard. Funnels already created do not change. ' \
      'Existing agents only change through the Update with the new base button.'
    )
  end

  it 'explica o que a escolha muda' do
    get "#{path}/edit"

    texto = Nokogiri::HTML(response.body).at_css('[data-agents-niche-form]').text.squish
    expect(texto).to include('Changes the words in the dashboard, the Guide, the Help Center and the agents to the way this account works.')
  end

  it 'mostra o "Como vende" só dentro do tipo de empresa, com os três canais' do
    get "#{path}/edit"

    document = Nokogiri::HTML(response.body)
    canais = document.css(%([data-agents-niche-profile] [data-agents-niche-channel] input[type="radio"][name="account[agents_niche][canal]"]))
    expect(canais.pluck('value')).to eq(%w[direto corretores parceiros])
    expect(canais.find { |radio| radio['checked'] }['value']).to eq('direto')
    expect(document.at_css('#agents-niche-perfil-insurtech')).to be_present
    expect(document.at_css('[data-agents-niche-channel] legend').text.squish).to eq('How it sells')
  end

  # Prévia do mockup aprovado (#1550): o texto real do pacote, no idioma da conta, uma prévia por escolha.
  it 'mostra a prévia de um card fechado para cada escolha, no idioma da conta' do
    account.update!(locale: 'pt_BR')
    get "#{path}/edit"

    document = Nokogiri::HTML(response.body)
    previas = document.css('[data-agents-niche-preview]').to_h do |previa|
      [previa['data-agents-niche-preview'], previa.css('[data-agents-niche-preview-chip]').map { |chip| chip.text.squish }]
    end
    expect(previas).to eq(
      'corretora' => ['Seguro ativo', 'Não fechou'], 'seguradora' => ['Seguro ativo', 'Não fechou'],
      'insurtech' => ['Seguro ativo', 'Não fechou'], 'saude_beneficios' => ['Implantado', 'Não fechou'],
      'geral' => %w[Ganho Perdido]
    )
    expect(document.css('[data-agents-niche-profile] [data-agents-niche-preview]').size).to eq(4)
    expect(document.at_css('[data-agents-niche-preview="saude_beneficios"]')['class'])
      .to include('group-has-[#agents-niche-perfil-saude-beneficios:checked]/perfil:flex')
  end

  # Rodada 2 (#1550): o Tailwind troca "_" por espaço dentro de [...]; com "_" no id, a prévia de saúde nunca aparecia.
  it 'aponta cada prévia para um rádio que existe, sem "_" no id' do
    get "#{path}/edit"

    document = Nokogiri::HTML(response.body)
    alvos = document.css('[data-agents-niche-preview]').map do |previa|
      classe = previa['class'].split.find { |nome| nome.start_with?('group-has-[#') }
      classe.delete_prefix('group-has-[#').split(':checked').first
    end
    expect(alvos.size).to eq(5)
    expect(alvos).to all(satisfy { |id| id.exclude?('_') && document.at_css("##{id}").present? })
  end

  it 'diz na prévia que é o efeito de quando ligar, enquanto as palavras por segmento estão desligadas' do
    get "#{path}/edit"
    desligado = Nokogiri::HTML(response.body).at_css('[data-agents-niche-preview="geral"] span').text.squish

    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') { get "#{path}/edit" }
    ligado = Nokogiri::HTML(response.body).at_css('[data-agents-niche-preview="geral"] span').text.squish

    expect(desligado).to eq('Once segment wording is turned on, a closed card will show as')
    expect(ligado).to eq("For this account's team, a closed card shows as")
  end

  it 'avisa que a escolha só fica guardada enquanto as palavras por segmento estão desligadas' do
    get "#{path}/edit"

    nota = Nokogiri::HTML(response.body).at_css('[data-agents-niche-form] [data-agents-niche-switch-off]')
    expect(nota).to be_present
    expect(nota['role']).to eq('note')
    expect(nota.text.squish).to start_with('While segment wording is turned off on this installation')
  end

  it 'não mostra o aviso de desligado quando as palavras por segmento estão ligadas' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') { get "#{path}/edit" }

    expect(Nokogiri::HTML(response.body).at_css('[data-agents-niche-switch-off]')).to be_nil
  end

  it 'liga cada cartão ao seu rótulo, com alvo de toque de 44 px' do
    get "#{path}/edit"

    document = Nokogiri::HTML(response.body)
    todos = radios(document, 'nicho') + radios(document, 'perfil') + radios(document, 'canal')
    expect(radios(document, 'canal').size).to eq(3)
    todos.each do |radio|
      label = radio.ancestors('label').first
      expect(label).to be_present
      expect(label['class'].split).to include('min-h-11')
    end
  end

  it 'não deixa rótulo apontando para um campo que não existe' do
    get "#{path}/edit"

    document = Nokogiri::HTML(response.body)
    expect(document.css('label[for="account_agents_niche"]')).to be_empty
    expect(document.at_css('[data-agents-niche-form] legend').text.squish).to eq('Account segment and niche')
  end

  # Insurtech gravada antes do canal existir lê "direto" (#1550).
  it 'mostra o nicho efetivo na página da conta' do
    account.update!(internal_attributes: account.internal_attributes.merge(nicho_key => 'seguros', perfil_key => 'insurtech'))

    get path

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('[data-agents-niche]').text.squish).to eq('Insurance · Insurtech · Direct to customer')
  end

  it 'grava nicho e perfil no update sem apagar as outras chaves de internal_attributes' do
    patch path, params: { account: { name: account.name, agents_niche: { nicho: 'seguros', perfil: 'seguradora' } } }

    expect(response).to have_http_status(:redirect)
    expect(account.reload.internal_attributes).to eq(
      'unrelated' => 'preserved', 'autonomia_insurance_enabled' => true, nicho_key => 'seguros', perfil_key => 'seguradora'
    )
  end

  it 'mostra o canal da insurtech no nome efetivo da conta' do
    account.update!(internal_attributes: account.internal_attributes.merge(nicho_key => 'seguros', perfil_key => 'insurtech',
                                                                           canal_key => 'parceiros'))

    get path

    expect(Nokogiri::HTML(response.body).at_css('[data-agents-niche]').text.squish).to eq('Insurance · Insurtech · Through partners')
  end

  it 'grava o canal da insurtech no update' do
    patch path, params: { account: { name: account.name, agents_niche: { nicho: 'seguros', perfil: 'insurtech', canal: 'corretores' } } }

    expect(response).to have_http_status(:redirect)
    expect(account.reload.internal_attributes).to eq(
      'unrelated' => 'preserved', 'autonomia_insurance_enabled' => true, nicho_key => 'seguros', perfil_key => 'insurtech',
      canal_key => 'corretores'
    )
  end

  it 'não grava canal quando o perfil não é insurtech' do
    patch path, params: { account: { name: account.name, agents_niche: { nicho: 'seguros', perfil: 'corretora', canal: 'corretores' } } }

    expect(account.reload.internal_attributes).to eq(
      'unrelated' => 'preserved', 'autonomia_insurance_enabled' => true, nicho_key => 'seguros', perfil_key => 'corretora'
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
