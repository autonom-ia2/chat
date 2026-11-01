FactoryBot.define do
  factory :crm_meta_ads_post_reading, class: 'Crm::MetaAdsPostReading' do
    account
    network { 'instagram' }
    sequence(:post_id) { |n| "1790000000#{n}" }
    description { 'Um vestido azul de linho num cabide, com fundo branco.' }
    model { 'gpt-teste' }
    read_at { Time.current }
  end
end
