require 'rails_helper'

# Quantas vezes o Guia pode ler antes de responder (#568, #572).
#
# Dez é decisão do Rodrigo — o número que ele já operava no n8n. Só é seguro
# porque o Guia responde num job: na requisição, o `rack-timeout` de produção
# mata tudo aos 15 segundos, e em 21/09/2026 duas leituras já davam erro 500.
#
# Os dois testes andam juntos de propósito. Se alguém trouxer o Guia de volta
# para dentro da requisição, o segundo quebra — e o número tem que cair junto.
RSpec.describe Autonomia::Guide::Chat do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }

  it 'deixa o Guia ler até dez vezes antes de responder' do
    agente = instance_double(Autonomia::Agents::Agent)
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(agente)
    allow(Autonomia::Agents::Retriever).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
    recebido = {}
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      recebido = kwargs
      instance_double(Autonomia::Agents::Answerer,
                      answer: Autonomia::Agents::AnswerResult.new(reply: 'ok', confidence: 1.0,
                                                                  handoff: { should: false, reason: nil }))
    end

    described_class.new(account: conta, user: admin, message: 'quantas conversas eu tenho?').perform

    expect(recebido[:max_rodadas]).to eq(10)
  end

  it 'nunca responde dentro da requisição: o controller só abre o pedido' do
    fonte = Rails.root.join('app/controllers/api/v1/accounts/autonomia/guide_controller.rb').read

    expect(fonte).not_to include('Guide::Chat.new')
  end
end
