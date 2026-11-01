FactoryBot.define do
  factory :autonomia_automacao, class: 'Autonomia::Automacao::Definicao' do
    account
    sequence(:nome) { |n| "Lembrete de retorno #{n}" }
    origem { 'manual' }
  end

  factory :autonomia_automacao_versao, class: 'Autonomia::Automacao::Versao' do
    automacao { association :autonomia_automacao }
    account { automacao.account }
    sequence(:numero) { |n| n }
    receita { { 'passos' => [] } }
  end

  factory :autonomia_automacao_execucao, class: 'Autonomia::Automacao::Execucao' do
    versao { association :autonomia_automacao_versao }
    automacao { versao.automacao }
    account { automacao.account }
    alvo { association :conversation, account: account }
    chave_gatilho { 'conversation_created' }
  end

  factory :autonomia_automacao_registro, class: 'Autonomia::Automacao::Registro' do
    execucao { association :autonomia_automacao_execucao }
    automacao { execucao.automacao }
    account { execucao.account }
    passo { 'p1' }
    resultado { 'ok' }
  end
end
