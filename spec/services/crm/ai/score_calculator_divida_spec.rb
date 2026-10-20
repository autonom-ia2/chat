require 'rails_helper'

# #1962 (fase 1 do #1961): a nota mede a DÍVIDA nossa com dado do sistema.
# Quem falou por último vem do banco (waiting_since); se a fala pede resposta nossa, o modelo diz
# (awaiting_our_reply). A dívida não esfria por 14 dias e expira depois deles; "pronto para fechar" é sinal
# forte; sinal negativo explícito zera na hora.
RSpec.describe Crm::Ai::ScoreCalculator do
  let(:now) { Time.zone.parse('2026-10-20 12:00:00') }

  # Base baixa de propósito: o que sobe a nota nestes exemplos é a regra testada, não os sinais.
  let(:morno) do
    { next_stage_readiness: 'parcial', intent: 'media', urgency: 'nenhuma', decision_maker: 'desconhecido',
      blocker: 'nenhum', buying_signal: false, awaiting_our_reply: true, unfulfilled_promise: false, unreadable: false }
  end
  let(:quente) { morno.merge(next_stage_readiness: 'pronta', intent: 'alta', decision_maker: 'sim') }

  # customer_waiting: true = no banco, a última fala real é do cliente e ele espera desde ela.
  def score(signals, idle_days: 0, customer_waiting: false)
    last = now - idle_days.days
    described_class.new(signals: signals, last_message_at: last, waiting_since: (last if customer_waiting), now: now).perform
  end

  describe 'quem espera: o banco diz quem falou, o modelo diz se pede resposta' do
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

    # "Obrigado", "vou pensar", "vou comparar": a última fala é do cliente, mas não há o que responder.
    it 'sem nada para responder, a última fala do cliente não vira dívida nossa' do
      sem_pedido = morno.merge(awaiting_our_reply: false, buying_signal: true)

      expect(score(sem_pedido, idle_days: 6, customer_waiting: true).value).to eq(score(sem_pedido, idle_days: 6).value)
      expect(score(sem_pedido, idle_days: 6, customer_waiting: true).breakdown[:customer_waiting]).to eq(0)
    end

    # Nota gravada antes do #1962 não tem o campo. O ScoreDecayJob recalcula sem IA e não pode subir uma nota
    # antiga com uma leitura que ela não tem (newsletter e e-mail automático chegam como `incoming`).
    it 'nota antiga, sem awaiting_our_reply, não conta espera' do
      antiga = morno.except(:awaiting_our_reply).merge(buying_signal: true)

      expect(score(antiga, idle_days: 5, customer_waiting: true).value).to eq(score(antiga, idle_days: 5).value)
    end

    it 'depois de 14 dias de espera cai a dívida inteira e esfria a partir do fim da validade' do
      result = score(morno, idle_days: 15, customer_waiting: true)

      expect(result.value).to be < described_class::CUSTOMER_WAITING_FLOOR
      expect(result.breakdown[:customer_waiting]).to eq(0)
      # 15 dias de espera: um dia depois da validade, ainda na carência. A nota é a da conversa, sem decaimento.
      expect(result.value).to eq(score(morno, idle_days: 0).value)
      expect(score(morno, idle_days: 30, customer_waiting: true).value).to be < result.value
    end

    it 'conta a validade em tempo exato: 14 dias e algumas horas já venceu' do
      last = now - 14.days - 9.hours
      result = described_class.new(signals: morno, last_message_at: last, waiting_since: last, now: now).perform

      expect(result.value).to be < described_class::CUSTOMER_WAITING_FLOOR
    end

    # O cliente pergunta numa conversa; nós falamos depois em outra. Ele espera desde a pergunta dele.
    it 'conta a espera desde a fala do cliente, não desde a última mensagem do card' do
      result = described_class.new(signals: quente, last_message_at: now - 1.day, waiting_since: now - 4.days, now: now).perform

      expect(result.breakdown[:customer_waiting]).to eq(described_class::CUSTOMER_WAITING_BONUS_BASE + (4 * 2))
    end

    it 'cliente esperando com pedido de compra na mesa e sem objeção é urgente' do
      expect(score(morno.merge(buying_signal: true), idle_days: 6, customer_waiting: true).tier).to eq('urgente')
    end

    it 'com objeção leve ("vou pensar", "achei caro") o piso é o de quente, não o de urgente' do
      result = score(morno.merge(buying_signal: true, blocker: 'leve'), idle_days: 1, customer_waiting: true)

      expect(result.tier).to eq('quente')
    end

    it 'recusa explícita não segura o piso de espera' do
      expect(score(morno.merge(blocker: 'forte'), idle_days: 3, customer_waiting: true).tier).to eq('frio')
    end
  end

  describe 'promessa com validade' do
    it 'vale até 14 dias de silêncio' do
      expect(score(morno.merge(unfulfilled_promise: true), idle_days: 14).tier).to eq('urgente')
    end

    it 'depois de 14 dias perde bônus e piso e esfria aos poucos, contando do fim da validade' do
      com_promessa = score(morno.merge(unfulfilled_promise: true), idle_days: 15)

      expect(com_promessa.breakdown[:unfulfilled_promise]).to eq(0)
      expect(com_promessa.value).to eq(score(morno, idle_days: 1).value)
      expect(score(morno.merge(unfulfilled_promise: true), idle_days: 20).value).to eq(score(morno, idle_days: 6).value)
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

    # A pendência é dele: o piso segura, mas o silêncio dele esfria a nota até o piso.
    it 'falta dado do cliente não pausa o decaimento' do
      alta = quente.merge(ready_to_close: 'falta_dado_do_cliente')

      expect(score(alta, idle_days: 10).value).to be < score(alta, idle_days: 0).value
      expect(score(alta, idle_days: 10).value).to be >= described_class::CUSTOMER_WAITING_FLOOR
    end

    it 'não se aplica pesa o mesmo que nota antiga sem o campo' do
      expect(score(morno.merge(ready_to_close: 'nao_se_aplica'), idle_days: 4).value).to eq(score(morno, idle_days: 4).value)
    end

    it 'depois de 14 dias de silêncio o piso não vale mais' do
      expect(score(morno.merge(ready_to_close: 'falta_dado_nosso'), idle_days: 20).value)
        .to be < described_class::CUSTOMER_WAITING_FLOOR
    end
  end

  describe 'sem mensagem real' do
    it 'não há dívida sem conversa: promessa e pronto para fechar não dão piso' do
      result = described_class.new(signals: morno.merge(unfulfilled_promise: true, ready_to_close: 'falta_dado_nosso'),
                                   last_message_at: nil, now: now).perform

      expect(result.value).to be < described_class::CUSTOMER_WAITING_FLOOR
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
    let(:schema) { Crm::Ai::ScoreSignalsSchema::SCHEMA }

    it 'pede pronto para fechar com saída "não se aplica" e o negativo explícito no blocker' do
      expect(schema[:properties][:ready_to_close][:enum]).to include('nao_se_aplica', 'falta_dado_nosso', 'falta_dado_do_cliente')
      expect(schema[:required]).to include('ready_to_close')
      expect(schema[:properties][:blocker][:enum]).to include('negativo_explicito')
    end

    it 'pede ao modelo só se a fala pede resposta, não quem falou por último' do
      expect(schema[:properties][:awaiting_our_reply][:type]).to eq('boolean')
      expect(schema[:properties]).not_to have_key(:last_turn_owner)
      expect(schema[:required]).not_to include('last_turn_owner')
      expect(schema[:required]).to match_array(schema[:properties].keys.map(&:to_s))
    end
  end
end
