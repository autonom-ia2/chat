FactoryBot.define do
  factory :carteira_apolice, class: 'Carteira::Apolice' do
    account
    contact { association :contact, account: account }
    tipo { 'auto' }
    seguradora { 'Seguradora Exemplo' }
    seguradora_chave { 'seguradoraexemplo' }
    sequence(:numero) { |n| "EX-#{n.to_s.rjust(6, '0')}" }
    sequence(:numero_chave) { |n| "EX#{n.to_s.rjust(6, '0')}" }
    fim_vigencia { 1.year.from_now.to_date }
    origem { 'planilha' }
  end
end
