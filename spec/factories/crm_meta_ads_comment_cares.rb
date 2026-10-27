FactoryBot.define do
  factory :crm_meta_ads_comment_care, class: 'Crm::MetaAdsCommentCare' do
    account
    target_kind { 'post' }
    sequence(:target_id) { |n| "1790000000#{n}" }
    network { 'instagram' }
    status { 'on' }
    offer { { 'offer' => 'Projeto de decoração', 'price' => 'a partir de R$ 490', 'how' => 'orçamento pelo WhatsApp' } }
    message { 'Oi! O projeto de decoração sai a partir de R$ 490. Quer um orçamento?' }
    phrases { ['Te chamei no privado 😊', 'Te mandei os detalhes no privado!', 'Olha o seu privado 💬'] }
    price_reply { 'A partir de R$ 490 😊 Te mandei os detalhes no privado.' }
    button { { 'title' => 'Chamar no WhatsApp', 'url' => 'https://wa.me/5511999990000' } }
    started_at { Time.current }
  end
end
