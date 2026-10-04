require 'rails_helper'

RSpec.describe TypesafeAi::Decisor do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'joana@cliente.com', phone_number: '+5511988887777') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, additional_attributes: { 'mail_subject' => 'Cotação' })
  end
  let!(:message) { create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'Quero cotar') }
  let(:decisor) { create(:autonomia_decisor, account: account, instrucoes: 'Newsletter nunca é lead.') }
  let(:estado) { Autonomia::Decisores::Estado.new(conversation: conversation, message: message) }
  let(:jev) { described_class.new(client: TypesafeAi::Client.new(api_key: 'ts_test_key_not_real', sleeper: ->(_) {}), model: 'jev-1.13.0') }

  def responder(choice: 'sim', confidence: 0.93, model: 'jev-1.13.0', status: 200)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(
      status: status,
      body: { model: model, usage: { input_tokens: 1_000, output_tokens: 3 },
              answers: { decisao: { type: 'choice', choice: choice, confidence: confidence } } }.to_json
    )
  end

  it 'decide com a pergunta e as respostas do Decisor, sem e-mail nem telefone do contato' do
    request = responder

    resultado = jev.decidir(decisor: decisor, estado: estado)

    expect(resultado.to_h).to eq(resposta: 'sim', certeza: 0.93, modelo: 'jev-1.13.0')
    expect(request).to have_been_made.once
    expect(a_request(:post, 'https://api.typesafe.ai/v1/systemone').with { |http| corpo_valido?(JSON.parse(http.body)) }).to have_been_made
  end

  def corpo_valido?(corpo)
    pergunta = corpo.dig('questions', 'decisao')
    pergunta['type'] == 'choice' && pergunta['criteria'].keys == %w[sim nao] &&
      corpo.dig('state', 'messages') == ['Quero cotar'] && corpo.dig('state', 'subject') == 'Cotação' &&
      corpo.to_json.exclude?('joana@cliente.com') && corpo.to_json.exclude?('988887777')
  end

  it 'devolve a certeza baixa como veio, para quem chamou tratar como dúvida' do
    responder(confidence: 0.4)

    expect(jev.decidir(decisor: decisor, estado: estado).certeza).to eq(0.4)
  end

  it 'recusa resposta fora das chaves do Decisor' do
    responder(choice: 'talvez')

    expect { jev.decidir(decisor: decisor, estado: estado) }.to raise_error(described_class::Error, 'typesafe_invalid_response')
  end

  it 'recusa resposta de outro modelo' do
    responder(model: 'jev-9')

    expect { jev.decidir(decisor: decisor, estado: estado) }.to raise_error(described_class::Error, 'typesafe_invalid_response')
  end

  it 'traduz a falha do provedor num código' do
    responder(status: 401)

    expect { jev.decidir(decisor: decisor, estado: estado) }.to raise_error(described_class::Error, 'typesafe_invalid_key')
  end

  it 'registra o custo do Jev em Crm::AiUsageEvent com o preço da tabela' do
    responder

    expect { jev.decidir(decisor: decisor, estado: estado) }.to change(Crm::AiUsageEvent, :count).by(1)
    evento = Crm::AiUsageEvent.last
    expect(evento).to have_attributes(account_id: account.id, feature: 'decisor', model: 'jev-1.13.0', input_tokens: 1_000, output_tokens: 3)
    expect(evento.cost_estimate.to_f).to be_within(1e-9).of(0.000042)
  end
end
