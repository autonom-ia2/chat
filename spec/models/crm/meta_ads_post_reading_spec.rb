require 'rails_helper'

RSpec.describe Crm::MetaAdsPostReading do
  let(:leitura) { build(:crm_meta_ads_post_reading) }

  it 'a correção do dono vale no lugar da descrição da IA' do
    expect(leitura.texto_para_ia).to eq('Um vestido azul de linho num cabide, com fundo branco.')

    leitura.correction = 'Vestido midi de linho, cor azul-marinho'
    expect(leitura.texto_para_ia).to eq('Vestido midi de linho, cor azul-marinho')
  end

  it 'sem descrição nem correção: nada vai à IA' do
    expect(build(:crm_meta_ads_post_reading, description: nil).texto_para_ia).to be_nil
  end

  it 'uma leitura por post da conta, só Instagram ou Facebook, com texto curto' do
    existente = create(:crm_meta_ads_post_reading)

    expect(build(:crm_meta_ads_post_reading, account: existente.account, post_id: existente.post_id)).not_to be_valid
    expect(build(:crm_meta_ads_post_reading, post_id: existente.post_id)).to be_valid
    expect(build(:crm_meta_ads_post_reading, network: 'tiktok')).not_to be_valid
    expect(build(:crm_meta_ads_post_reading, correction: 'a' * 1001)).not_to be_valid
  end
end
