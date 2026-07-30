require 'rails_helper'

# GOLDEN SET da calibração do score.
#
# Cada caso vem de uma conversa real (conta 18 = seguro viagem, conta 6 = seguro de transporte) ou
# de um cenário sintético de outro tipo de agente (suporte, agendamento). O conjunto trava DUAS
# coisas: a faixa de cada caso e a ORDEM relativa entre eles.
#
# Regra de manutenção: recalibrar pesos SÓ passa se o golden set inteiro continuar verde. Um ajuste
# que conserta um caso quebrando outro aparece aqui antes de chegar em produção.
RSpec.describe Crm::Ai::ScoreCalculator do
  def now = Time.zone.parse('2026-07-30 12:00:00')

  def score(signals, idle_days: 0)
    described_class.new(signals: signals, last_message_at: now - idle_days.days, now: now).perform
  end

  # ── Vendas · conta 18 (seguro viagem) ────────────────────────────────────────
  def promessa_quebrada
    # Card 366: cliente quis pagar, bot prometeu o link 8x e sumiu. 20 dias parado.
    score({ next_stage_readiness: 'inicial', intent: 'alta', urgency: 'imediata', decision_maker: 'desconhecido',
            blocker: 'nenhum', last_turn_owner: 'humano', buying_signal: true, unfulfilled_promise: true }, idle_days: 20)
  end

  def pediu_parcelamento
    # Card 1126: viu o preço, perguntou valor total e parcelas, "vou estudar".
    score({ next_stage_readiness: 'parcial', intent: 'alta', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'leve', last_turn_owner: 'humano', buying_signal: true }, idle_days: 1)
  end

  def reclamou_do_preco
    # Card 1148: recebeu comparativo, "tá muito caro". Negociando, não desistindo.
    score({ next_stage_readiness: 'inicial', intent: 'alta', urgency: 'futura', decision_maker: 'desconhecido',
            blocker: 'leve', last_turn_owner: 'humano', buying_signal: true }, idle_days: 1)
  end

  def sem_qualificacao
    # Card 572: conversa sem dados, áudios sem transcrição.
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'nenhum', last_turn_owner: 'cliente', unreadable: true }, idle_days: 21)
  end

  def fora_de_escopo
    # Card 982: queria seguro de carro, corretora só faz viagem.
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'forte', last_turn_owner: 'cliente' }, idle_days: 7)
  end

  # ── Vendas · conta 6 (seguro de transporte) ──────────────────────────────────
  def mandou_documentos
    # Card 1164: cliente enviou CNPJ, placa, regiões e teto de valor espontaneamente.
    score({ next_stage_readiness: 'pronta', intent: 'alta', urgency: 'proxima', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'cliente', buying_signal: true }, idle_days: 0)
  end

  def comparando_concorrentes
    # Card 1103: "ainda estou aguardando umas propostas". Vivo, mas travado em comparação.
    score({ next_stage_readiness: 'parcial', intent: 'media', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'leve', last_turn_owner: 'humano' }, idle_days: 2)
  end

  def ghosting_com_followup
    # Card 1134: follow-ups repetidos há 19 dias, sem resposta útil.
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'nenhum', last_turn_owner: 'humano' }, idle_days: 19)
  end

  # ── Outros tipos de agente (o score é genérico) ──────────────────────────────
  def suporte_cliente_travado
    # Cliente repetiu a pergunta, está bloqueado e cobrou; nós devemos resposta.
    score({ next_stage_readiness: 'parcial', intent: 'alta', urgency: 'imediata', decision_maker: 'desconhecido',
            blocker: 'nenhum', last_turn_owner: 'cliente' }, idle_days: 0)
  end

  def suporte_resolvido
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'nenhum', last_turn_owner: 'humano' }, idle_days: 1)
  end

  def consulta_amanha_sem_confirmacao
    score({ next_stage_readiness: 'parcial', intent: 'media', urgency: 'imediata', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'humano' }, idle_days: 2)
  end

  it 'coloca os casos que merecem atenção nas faixas altas' do
    expect(promessa_quebrada.tier).to eq('urgente')
    expect(mandou_documentos.tier).to eq('urgente')
    expect(pediu_parcelamento.tier).to eq('quente')
    expect(suporte_cliente_travado.tier).to eq('quente')
    expect(consulta_amanha_sem_confirmacao.tier).to eq('quente')
    expect(reclamou_do_preco.tier).to eq('morno')
    expect(comparando_concorrentes.tier).to eq('morno')
  end

  it 'esfria quem não dá sinal de vida ou saiu do jogo' do
    expect(sem_qualificacao.tier).to eq('frio')
    expect(fora_de_escopo.tier).to eq('frio')
    expect(ghosting_com_followup.tier).to eq('frio')
    expect(suporte_resolvido.tier).to eq('frio')
  end

  it 'ordena a fila como um operador ordenaria' do
    fila = [promessa_quebrada, mandou_documentos, suporte_cliente_travado, pediu_parcelamento,
            consulta_amanha_sem_confirmacao, reclamou_do_preco, comparando_concorrentes,
            fora_de_escopo, ghosting_com_followup]

    expect(fila.map(&:value)).to eq(fila.map(&:value).sort.reverse)
  end

  it 'distingue os dois urgentes entre si em vez de saturar ambos em 100' do
    expect(promessa_quebrada.value).to be > mandou_documentos.value
  end
end
