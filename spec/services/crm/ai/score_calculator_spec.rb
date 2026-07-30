require 'rails_helper'

RSpec.describe Crm::Ai::ScoreCalculator do
  let(:now) { Time.zone.parse('2026-07-30 12:00:00') }

  def score(signals, last_message_at: now, terminal: false)
    described_class.new(signals: signals, last_message_at: last_message_at, terminal: terminal, now: now).perform
  end

  # Espelha o card 366 do teste sombra (conta 18): cliente quis pagar, o bot prometeu o link 8x e
  # nunca entregou, 20 dias parado. Precisa ficar no topo APESAR do silêncio.
  it 'puts an unfulfilled promise at the top and ignores the time decay' do
    result = score(
      {
        next_stage_readiness: 'parcial', intent: 'alta', urgency: 'proxima', decision_maker: 'sim',
        blocker: 'nenhum', last_turn_owner: 'agente_plataforma', unfulfilled_promise: true,
        reason: 'Link de pagamento prometido e nunca enviado.'
      },
      last_message_at: now - 20.days
    )

    expect(result.value).to eq(98)
    expect(result.tier).to eq('urgente')
    expect(result.reason).to eq('Link de pagamento prometido e nunca enviado.')
  end

  it 'ranks a lead ready for the next stage above one that just received the proposal' do
    ready = score(
      { next_stage_readiness: 'pronta', intent: 'alta', urgency: 'proxima', decision_maker: 'sim',
        blocker: 'leve', last_turn_owner: 'humano', unfulfilled_promise: false },
      last_message_at: now - 1.day
    )
    early = score(
      { next_stage_readiness: 'parcial', intent: 'alta', urgency: 'futura', decision_maker: 'desconhecido',
        blocker: 'nenhum', last_turn_owner: 'agente_plataforma', unfulfilled_promise: false },
      last_message_at: now - 12.hours
    )

    expect(ready.value).to be > early.value
    expect(ready.tier).to eq('quente')
  end

  it 'decays from the last message and never below zero' do
    signals = { next_stage_readiness: 'inicial', intent: 'media', urgency: 'nenhuma',
                decision_maker: 'desconhecido', blocker: 'nenhum', last_turn_owner: 'humano' }

    expect(score(signals, last_message_at: now - 1.day).value).to eq(13)
    expect(score(signals, last_message_at: now - 10.days).value).to eq(0)
  end

  it 'caps the score when the conversation is unreadable' do
    result = score(
      { next_stage_readiness: 'pronta', intent: 'alta', urgency: 'imediata', decision_maker: 'sim',
        blocker: 'nenhum', last_turn_owner: 'cliente', unfulfilled_promise: false, unreadable: true }
    )

    expect(result.value).to eq(described_class::UNREADABLE_CAP)
    expect(result.tier).to eq('frio')
  end

  it 'zeroes a terminal card regardless of the signals' do
    result = score({ next_stage_readiness: 'pronta', intent: 'alta', urgency: 'imediata' }, terminal: true)

    expect(result.value).to eq(0)
    expect(result.reason).to eq('Card encerrado.')
  end

  it 'rewards the client speaking last, because we owe the reply' do
    base = { next_stage_readiness: 'parcial', intent: 'media', urgency: 'nenhuma',
             decision_maker: 'desconhecido', blocker: 'nenhum' }

    client_waiting = score(base.merge(last_turn_owner: 'cliente'))
    we_replied = score(base.merge(last_turn_owner: 'humano'))

    expect(client_waiting.value - we_replied.value).to eq(15)
  end
end
