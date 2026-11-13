FactoryBot.define do
  factory :carteira_leitura, class: 'Carteira::Leitura' do
    account
    origem { 'pdf' }
  end

  factory :carteira_leitura_item, class: 'Carteira::LeituraItem' do
    leitura factory: :carteira_leitura
    sequence(:posicao) { |n| n }
  end
end
