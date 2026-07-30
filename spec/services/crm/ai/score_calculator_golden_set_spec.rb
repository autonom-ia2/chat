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

  # ── Expansão: 20 casos reais adicionais (contas 18, 6, 16 e 3) ───────────────
  # Conta 18 · viagem
  def lilian_aceitou_e_ficou_no_vacuo
    # Card 573: 82 anos, Espanha em setembro, "30 euros tá ótimo" — e o especialista prometido nunca voltou.
    score({ next_stage_readiness: 'pronta', intent: 'alta', urgency: 'proxima', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'cliente', buying_signal: true, unfulfilled_promise: true }, idle_days: 21)
  end

  def ludmila_interesse_sem_viagem
    # Card 752: preencheu formulário, mas "quando tiver uma viagem definida". 14 dias.
    score({ next_stage_readiness: 'inicial', intent: 'media', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'nenhum', last_turn_owner: 'humano' }, idle_days: 14)
  end

  def marta_recusa_educada
    # Card 1115: precisa de cobertura que não existe; recusa definitiva, elogiou e saiu.
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'forte', last_turn_owner: 'cliente' }, idle_days: 2)
  end

  def claudemir_fechou_com_concorrente
    # Card 952: "fechamos com a Porto Seguro".
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'forte', last_turn_owner: 'humano' }, idle_days: 6)
  end

  def pediu_produto_de_outro_funil
    # Card 981: pediu RCP médico no funil de viagem.
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'forte', last_turn_owner: 'humano' }, idle_days: 7)
  end

  def so_disse_oi
    # Card 993: "Oi" e nada mais.
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'nenhum', last_turn_owner: 'humano' }, idle_days: 7)
  end

  # Conta 18 · RC médico
  def cotacao_na_mesa_aguardando_sim
    # Card 1154: cotação Akad 500k apresentada hoje, "quer seguir com essa opção?".
    score({ next_stage_readiness: 'pronta', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'humano', buying_signal: true }, idle_days: 0)
  end

  def qualificacao_quente_que_esfriou
    # Card 367: respondia limites e retroatividade; parou há 27 dias.
    score({ next_stage_readiness: 'parcial', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'cliente', buying_signal: true }, idle_days: 27)
  end

  def no_momento_nao
    # Card 645: "No momento não" — recusa suave, retomável. 17 dias.
    score({ next_stage_readiness: 'inicial', intent: 'media', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'leve', last_turn_owner: 'humano' }, idle_days: 17)
  end

  def cliente_pediu_reemissao_e_ficou_no_vacuo
    # Card 814: emissão falhou, cliente pediu para tentar de novo 2x; respondemos com desconfiança e sumimos.
    score({ next_stage_readiness: 'inicial', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'humano', buying_signal: true, unfulfilled_promise: true }, idle_days: 9)
  end

  def nao_preciso_deste_servico
    # Card 429: "Não preciso deste serviço. Vamos parar por aqui."
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'forte', last_turn_owner: 'cliente' }, idle_days: 20)
  end

  def lead_hostil
    # Card 369: "Que porcaria é essa. Vou te denunciar!"
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'forte', last_turn_owner: 'humano' }, idle_days: 27)
  end

  # Conta 6 · transporte
  def respondeu_opa_e_parou
    # Card 1029: pedimos o CNPJ, respondeu "Opa" e parou. 2 dias.
    score({ next_stage_readiness: 'inicial', intent: 'media', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'humano' }, idle_days: 2)
  end

  def decisor_e_a_esposa
    # Card 1094: "vou ver com minha esposa, é ela que cuida dessa parte; vamos marcar".
    score({ next_stage_readiness: 'parcial', intent: 'media', urgency: 'nenhuma', decision_maker: 'nao',
            blocker: 'nenhum', last_turn_owner: 'humano' }, idle_days: 2)
  end

  def qualificacao_ativa_agora
    # Card 1157: mandando dados de embarque em tempo real.
    score({ next_stage_readiness: 'parcial', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'cliente' }, idle_days: 0)
  end

  def proposta_enviada_e_ligacao_feita
    # Card 996: cotações enviadas, ligamos e explicamos, aguardando retorno — hoje.
    score({ next_stage_readiness: 'parcial', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'humano', buying_signal: true }, idle_days: 0)
  end

  def vamos_fechar_com_pdf
    # Card 1153: "R$ 350 cada apólice. Vamos fechar?" + PDF enviado hoje.
    score({ next_stage_readiness: 'pronta', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'humano', buying_signal: true }, idle_days: 0)
  end

  def pediu_recotacao_de_cenario
    # Card 1121: "quero sim" verificar o cenário novo; perguntando sobre a análise.
    score({ next_stage_readiness: 'parcial', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'cliente', buying_signal: true }, idle_days: 0)
  end

  def followups_automaticos_ignorados
    # Card 1092: quatro follow-ups desde 02/07, nenhuma resposta.
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'nenhum', last_turn_owner: 'humano' }, idle_days: 28)
  end

  def email_de_marketing_irrelevante
    # Card 902 (funil Email): newsletter de produto, não é lead.
    score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
            blocker: 'nenhum', last_turn_owner: 'cliente' }, idle_days: 8)
  end

  # Conta 16 · venda de plataforma (bot) e conta 3 · agência GTA
  def encaminhado_ao_comercial_e_esquecido
    # Card 694: bot prometeu encaminhamento à corretora; cliente disse "Ok" e ninguém voltou em 16 dias.
    score({ next_stage_readiness: 'parcial', intent: 'media', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'agente_plataforma', unfulfilled_promise: true }, idle_days: 16)
  end

  def engajado_que_esfriou
    # Card 455: queria o agente como SDR, perguntava detalhes — e sumiu há 24 dias.
    score({ next_stage_readiness: 'parcial', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'agente_plataforma' }, idle_days: 24)
  end

  def cotacao_gta_apresentada_hoje
    # Card 458: três opções apresentadas, "qual plano vamos seguir?".
    score({ next_stage_readiness: 'parcial', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'humano', buying_signal: true }, idle_days: 0)
  end

  def operadora_aguardando_cliente_final
    # Card 1061: agência ativa hoje, mas aguardando o cliente final dela decidir.
    score({ next_stage_readiness: 'parcial', intent: 'media', urgency: 'nenhuma', decision_maker: 'nao',
            blocker: 'nenhum', last_turn_owner: 'humano' }, idle_days: 0)
  end

  def reativou_pedindo_cotacao
    # Card 62: sumido desde junho, voltou hoje pedindo cotação.
    score({ next_stage_readiness: 'inicial', intent: 'alta', urgency: 'nenhuma', decision_maker: 'sim',
            blocker: 'nenhum', last_turn_owner: 'humano', buying_signal: true }, idle_days: 0)
  end

  it 'promessa nossa em aberto vence o silencio, em qualquer conta' do
    expect(lilian_aceitou_e_ficou_no_vacuo.tier).to eq('urgente')
    expect(cliente_pediu_reemissao_e_ficou_no_vacuo.tier).to eq('urgente')
    # Regra de produto (piso 85): promessa nossa esquecida é urgente mesmo vinda de bot.
    expect(encaminhado_ao_comercial_e_esquecido.tier).to eq('urgente')
  end

  it 'proposta na mesa hoje e pedido de cotacao ativo sao quentes' do
    expect(cotacao_na_mesa_aguardando_sim.tier).to eq('quente')
    # Revisado na calibração: cliente mandando dados AGORA merece resposta agora — manter o embalo.
    expect(qualificacao_ativa_agora.tier).to eq('quente')
    expect(proposta_enviada_e_ligacao_feita.tier).to eq('quente')
    expect(vamos_fechar_com_pdf.tier).to eq('quente')
    expect(pediu_recotacao_de_cenario.tier).to eq('quente')
    expect(cotacao_gta_apresentada_hoje.tier).to eq('quente')
    expect(reativou_pedindo_cotacao.tier).to eq('quente')
  end

  it 'engajamento real sem pedido de compra fica morno' do
    # Revisado na calibração: "Opa" anteontem é presença; falta só o CNPJ — cutucar hoje é razoável.
    expect(respondeu_opa_e_parou.tier).to eq('morno')
    expect(qualificacao_quente_que_esfriou.tier).to eq('morno')
    expect(decisor_e_a_esposa.tier).to eq('morno')
    expect(operadora_aguardando_cliente_final.tier).to eq('morno')
  end

  it 'recusa, hostilidade e fora de escopo esfriam na hora' do
    expect(marta_recusa_educada.tier).to eq('frio')
    expect(claudemir_fechou_com_concorrente.tier).to eq('frio')
    expect(pediu_produto_de_outro_funil.tier).to eq('frio')
    expect(nao_preciso_deste_servico.tier).to eq('frio')
    expect(lead_hostil.tier).to eq('frio')
  end

  it 'silencio e ruido esfriam com o tempo' do
    expect(ludmila_interesse_sem_viagem.tier).to eq('frio')
    expect(so_disse_oi.tier).to eq('frio')
    expect(no_momento_nao.tier).to eq('frio')
    expect(followups_automaticos_ignorados.tier).to eq('frio')
    expect(email_de_marketing_irrelevante.tier).to eq('frio')
    expect(engajado_que_esfriou.tier).to eq('frio')
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

  # Casos de conflito apontados pelo review adversarial (codex): as combinações não existiam no corpus.
  it 'recusa explicita cancela o piso da promessa' do
    result = score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'sim',
                     blocker: 'forte', last_turn_owner: 'cliente', unfulfilled_promise: true }, idle_days: 1)
    expect(result.tier).to eq('frio')
  end

  it 'ilegivel limita ate promessa: teto de confianca vem por ultimo' do
    result = score({ next_stage_readiness: 'nenhuma', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
                     blocker: 'nenhum', last_turn_owner: 'humano', unfulfilled_promise: true, unreadable: true }, idle_days: 1)
    expect(result.value).to eq(described_class::UNREADABLE_CAP)
  end

  it 'sem teto de decaimento, ate a base mais alta chega a frio com silencio longo' do
    result = score({ next_stage_readiness: 'pronta', intent: 'alta', urgency: 'imediata', decision_maker: 'sim',
                     blocker: 'nenhum', last_turn_owner: 'humano', buying_signal: true }, idle_days: 60)
    expect(result.tier).to eq('frio')
  end

  it 'distingue os dois urgentes entre si em vez de saturar ambos em 100' do
    expect(promessa_quebrada.value).to be > mandou_documentos.value
  end
end
