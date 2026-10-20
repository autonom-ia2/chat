require 'rails_helper'

# #1962 (fase 1 do #1961): a nota mede a DÍVIDA nossa com dado do sistema.
# Quem espera vem do banco (customer_waiting), não do modelo; a dívida não esfria por 14 dias e
# expira depois deles; "pronto para fechar" é sinal forte; sinal negativo explícito zera na hora.
RSpec.describe Crm::Ai::ScoreCalculator do
  let(:now) { Time.zone.parse('2026-10-20 12:00:00') }

  # Base baixa de propósito: o que sobe a nota nestes exemplos é a regra testada, não os sinais.
  let(:morno) do
    { next_stage_readiness: 'parcial', intent: 'media', urgency: 'nenhuma', decision_maker: 'desconhecido',
      blocker: 'nenhum', buying_signal: false, unfulfilled_promise: false, unreadable: false }
  end
  let(:quente) { morno.merge(next_stage_readiness: 'pronta', intent: 'alta', decision_maker: 'sim') }

  def score(signals, idle_days: 0, customer_waiting: false)
    described_class.new(signals: signals, last_message_at: now - idle_days.days,
                        customer_waiting: customer_waiting, now: now).perform
  end

  describe 'quem espera vem do banco' do
    it 'ignora o last_turn_owner que o modelo gravava nas notas antigas' do
      expect(score(morno.merge(last_turn_owner: 'cliente')).value).to eq(score(morno.merge(last_turn_owner: 'humano')).value)
    end

    it 'dá um bônus que cresce com a espera até o limite, sem decair' do
      valores = [0, 2, 5, 10].map { |dias| score(quente, idle_days: dias, customer_waiting: true).value }

      expect(valores).to eq(valores.sort)
      expect(valores.first).to be < valores.last
      expect(score(quente, idle_days: 10, customer_waiting: true).value)
        .to eq(score(quente, idle_days: 14, customer_waiting: true).value)
      expect(score(quente, idle_days: 0, customer_waiting: true).breakdown[:customer_waiting])
        .to eq(described_class::CUSTOMER_WAITING_BONUS_BASE)
      expect(score(quente, idle_days: 14, customer_waiting: true).breakdown[:customer_waiting])
        .to eq(described_class::CUSTOMER_WAITING_BONUS_MAX)
    end

    it 'segura o cliente esperando no piso até 14 dias' do
      result = score(morno, idle_days: 14, customer_waiting: true)

      expect(result.value).to eq(described_class::CUSTOMER_WAITING_FLOOR)
      expect(result.tier).to eq('quente')
    end

    it 'volta a esfriar depois de 14 dias de espera: sai o piso, fica o bônus, volta o decaimento' do
      result = score(morno, idle_days: 15, customer_waiting: true)

      expect(result.value).to be < described_class::CUSTOMER_WAITING_FLOOR
      expect(result.breakdown[:customer_waiting]).to eq(described_class::CUSTOMER_WAITING_BONUS_MAX)
      expect(score(morno, idle_days: 30, customer_waiting: true).tier).to eq('frio')
    end

    it 'conta a validade em tempo exato: 14 dias e algumas horas já venceu' do
      result = described_class.new(signals: morno, last_message_at: now - 14.days - 9.hours,
                                   customer_waiting: true, now: now).perform

      expect(result.value).to be < described_class::CUSTOMER_WAITING_FLOOR
    end

    it 'cliente esperando com pedido de compra na mesa é urgente' do
      expect(score(morno.merge(buying_signal: true), idle_days: 6, customer_waiting: true).tier).to eq('urgente')
    end

    it 'recusa explícita não segura o piso de espera' do
      expect(score(morno.merge(blocker: 'forte'), idle_days: 3, customer_waiting: true).tier).to eq('frio')
    end
  end

  describe 'promessa com validade' do
    it 'vale até 14 dias de silêncio' do
      expect(score(morno.merge(unfulfilled_promise: true), idle_days: 14).tier).to eq('urgente')
    end

    it 'depois de 14 dias a promessa decai como o resto' do
      com_promessa = score(morno.merge(unfulfilled_promise: true), idle_days: 15)

      expect(com_promessa.value).to eq(score(morno, idle_days: 15).value)
      expect(com_promessa.breakdown[:unfulfilled_promise]).to eq(0)
    end
  end

  describe 'pronto para fechar, falta só um dado' do
    it 'falta dado nosso é dívida nossa: urgente até 14 dias' do
      result = score(morno.merge(ready_to_close: 'falta_dado_nosso'), idle_days: 9)

      expect(result.tier).to eq('urgente')
    end

    it 'falta dado do cliente: pelo menos quente até 14 dias' do
      result = score(morno.merge(ready_to_close: 'falta_dado_do_cliente'), idle_days: 9)

      expect(result.value).to be >= described_class::CUSTOMER_WAITING_FLOOR
    end

    it 'não se aplica pesa o mesmo que nota antiga sem o campo' do
      expect(score(morno.merge(ready_to_close: 'nao_se_aplica'), idle_days: 4).value).to eq(score(morno, idle_days: 4).value)
    end

    it 'depois de 14 dias de silêncio o piso não vale mais' do
      expect(score(morno.merge(ready_to_close: 'falta_dado_nosso'), idle_days: 20).tier).to eq('frio')
    end
  end

  describe 'sinal negativo explícito' do
    it 'derruba na hora, mesmo com promessa, espera e pedido de compra' do
      result = score(
        quente.merge(blocker: 'negativo_explicito', buying_signal: true, unfulfilled_promise: true,
                     ready_to_close: 'falta_dado_nosso'),
        idle_days: 1, customer_waiting: true
      )

      expect(result.value).to eq(0)
      expect(result.tier).to eq('frio')
    end
  end

  describe 'contrato do modelo' do
    let(:schema) { described_class::SIGNALS_SCHEMA }

    it 'pede pronto para fechar com saída "não se aplica" e o negativo explícito no blocker' do
      expect(schema[:properties][:ready_to_close][:enum]).to include('nao_se_aplica', 'falta_dado_nosso', 'falta_dado_do_cliente')
      expect(schema[:required]).to include('ready_to_close')
      expect(schema[:properties][:blocker][:enum]).to include('negativo_explicito')
    end

    it 'não pede mais ao modelo quem falou por último' do
      expect(schema[:properties]).not_to have_key(:last_turn_owner)
      expect(schema[:required]).not_to include('last_turn_owner')
      expect(schema[:required]).to match_array(schema[:properties].keys.map(&:to_s))
    end
  end
end
