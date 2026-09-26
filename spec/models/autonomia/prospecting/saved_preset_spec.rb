require 'rails_helper'

# Jogadas salvas (#732, MODO-25, FILTRO-27, PLAT-17): os filtros da gaveta viram jogada da conta. O servidor só guarda
# as chaves da gaveta, com os valores que ela produz; nada de hash arbitrário.
RSpec.describe Autonomia::Prospecting::SavedPreset do
  let(:account) { create(:account) }

  def build_preset(filters, attributes = {})
    described_class.new({ account: account, name: 'Sem site e bem avaliadas', score_mode: 'gbp', filters: filters }.merge(attributes))
  end

  it 'guarda só os filtros preenchidos, com números como números' do
    preset = build_preset(
      'has_website' => 'no', 'has_phone' => '', 'rating_min' => '4.2', 'reviews_min' => '10', 'search_rank_max' => 20,
      'outside_top' => nil, 'open_now' => 'yes'
    )

    expect(preset).to be_valid
    expect(preset.filters).to eq('has_website' => 'no', 'rating_min' => 4.2, 'reviews_min' => 10, 'search_rank_max' => 20, 'open_now' => 'yes')
  end

  it 'recusa chave que a gaveta não tem' do
    preset = build_preset('has_website' => 'no', 'query' => 'drop table')

    expect(preset).not_to be_valid
    expect(preset.errors.full_messages).to include(I18n.t('autonomia.prospecting.saved_presets.errors.invalid_filters'))
  end

  it 'recusa valor fora do que a gaveta produz' do
    [
      { 'has_website' => 'talvez' },
      { 'open_now' => 'no' },
      { 'rating_min' => '6' },
      { 'rating_max' => '-1' },
      { 'reviews_min' => '2.5' },
      { 'reviews_min' => '10001' },
      { 'search_rank_max' => '61' },
      { 'outside_top' => '0' },
      { 'rating_min' => { 'nested' => 1 } },
      { 'rating_min' => 'quatro' }
    ].each do |filters|
      expect(build_preset(filters)).not_to be_valid, "aceitou #{filters.inspect}"
    end
  end

  it 'recusa avaliação mínima acima da máxima' do
    expect(build_preset('rating_min' => 4.5, 'rating_max' => 3)).not_to be_valid
  end

  it 'recusa jogada sem filtro nenhum' do
    preset = build_preset('has_website' => '', 'rating_min' => nil)

    expect(preset).not_to be_valid
    expect(preset.errors.full_messages).to include(I18n.t('autonomia.prospecting.saved_presets.errors.empty_filters'))
  end

  it 'recusa filtros que não são um objeto' do
    expect(build_preset(['has_website'])).not_to be_valid
  end

  it 'exige nome, com tamanho limitado e sem repetir na conta, ignorando maiúsculas e espaços' do
    build_preset({ 'has_website' => 'no' }).save!

    expect(build_preset({ 'has_phone' => 'yes' }, name: '  ')).not_to be_valid
    expect(build_preset({ 'has_phone' => 'yes' }, name: 'x' * 61)).not_to be_valid
    repeated = build_preset({ 'has_phone' => 'yes' }, name: '  SEM SITE E BEM AVALIADAS ')
    expect(repeated).not_to be_valid
    expect(repeated.errors.full_messages).to include(I18n.t('autonomia.prospecting.saved_presets.errors.name_taken'))
    expect(described_class.new(account: create(:account), name: 'Sem site e bem avaliadas', score_mode: 'gbp',
                               filters: { 'has_website' => 'no' })).to be_valid
  end

  it 'aceita só os modos da busca' do
    expect(build_preset({ 'has_website' => 'no' }, score_mode: 'general')).to be_valid
    expect(build_preset({ 'has_website' => 'no' }, score_mode: 'outro')).not_to be_valid
  end

  it 'para no limite de jogadas por conta' do
    stub_const("#{described_class}::MAX_PER_ACCOUNT", 2)
    2.times { |index| build_preset({ 'reviews_min' => index + 1 }, name: "Jogada #{index}").save! }

    extra = build_preset({ 'has_website' => 'no' }, name: 'Terceira')
    expect(extra).not_to be_valid
    expect(extra.errors.full_messages).to include(I18n.t('autonomia.prospecting.saved_presets.errors.limit', max: 2))
    expect(build_preset({ 'has_website' => 'no' }, account: create(:account), name: 'Terceira')).to be_valid
  end

  it 'o id da jogada salva na busca é o prefixo mais o id, e só acha na conta e no modo dela' do
    preset = build_preset({ 'has_website' => 'no' })
    preset.save!

    expect(preset.preset_id).to eq("saved-#{preset.id}")
    expect(described_class.find_by_preset_id(account, "saved-#{preset.id}")).to eq(preset)
    expect(described_class.find_by_preset_id(create(:account), "saved-#{preset.id}")).to be_nil
    expect(described_class.find_by_preset_id(account, "saved-#{preset.id}x")).to be_nil
    expect(described_class.find_by_preset_id(account, 'vender-site')).to be_nil
    expect(described_class.find_by_preset_id(account, preset.id.to_s)).to be_nil
  end
end
