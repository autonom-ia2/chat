require 'rails_helper'

# O aquecimento do Guia depois do deploy (#636): hoje `Seed.ensure_async_for` só roda quando
# alguém usa o Guia, e a primeira pergunta paga o cache frio. Este job chama o mesmo método,
# sozinho, para toda conta elegível — sem repetir a lógica de elegibilidade nem de dedupe, que já
# moram em `Seed`.
RSpec.describe Autonomia::Guide::WarmUpJob do
  let(:elegivel) { create_account_and_user.first }
  let(:inelegivel) { create_account_and_user.first }

  it 'aquece só as contas elegíveis, e pula as que não são', :aggregate_failures do
    # `let` é preguiçoso: força as duas contas a existir ANTES do `perform`, senão o
    # `Account.find_each` do job roda sem achar nenhuma — e a asserção lá embaixo, ao citar
    # `elegivel`, criaria a conta tarde demais para o job ter visto.
    conta_elegivel = elegivel
    conta_inelegivel = inelegivel

    allow(Autonomia::Guide::Seed).to receive(:eligible?) do |account|
      account.id == conta_elegivel.id
    end
    allow(Autonomia::Guide::Seed).to receive(:ensure_async_for)

    described_class.new.perform

    expect(Autonomia::Guide::Seed).to have_received(:ensure_async_for).with(conta_elegivel)
    expect(Autonomia::Guide::Seed).not_to have_received(:ensure_async_for).with(conta_inelegivel)
  end
end
