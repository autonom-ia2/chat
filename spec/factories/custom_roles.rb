FactoryBot.define do
  factory :custom_role do
    account
    # Nome único por conta (#2185): o número evita colisão do Faker entre funções da mesma conta.
    sequence(:name) { |n| "#{Faker::Name.name} #{n}" }
    description { Faker::Lorem.sentence }
    permissions { CustomRole::PERMISSIONS.sample(SecureRandom.random_number(1..4)) }
  end
end
