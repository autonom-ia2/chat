FactoryBot.define do
  factory :autonomia_decisor, class: 'Autonomia::Decisor' do
    account
    sequence(:nome) { |n| "É lead? #{n}" }
    pergunta { 'Este e-mail é de alguém interessado em contratar seguro?' }
    respostas do
      [{ 'chave' => 'sim', 'descricao' => 'Pede cotação ou informação de seguro' },
       { 'chave' => 'nao', 'descricao' => 'Newsletter, fornecedor ou aviso automático' }]
    end
    certeza_minima { 0.8 }
  end

  factory :autonomia_decisor_decisao, class: 'Autonomia::DecisorDecisao' do
    decisor { association :autonomia_decisor }
    account { decisor.account }
    conversation { association :conversation, account: account }
    message { association :message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming }
    status { 'decidida' }
    resposta { 'sim' }
    certeza { 0.95 }
  end
end
