# Contrato de saída do modelo para a nota do card (Crm::Ai::ScoreCalculator pesa estes sinais; o StageClassifier só
# consome). Mora fora da calculadora para ela ficar com os pesos e as regras (#1962).
module Crm::Ai::ScoreSignalsSchema
  SCHEMA = {
    type: 'object',
    description: 'Sinais para pontuar a prioridade de atenção humana neste card.',
    properties: {
      next_stage_readiness: {
        type: 'string',
        enum: %w[nenhuma inicial parcial pronta],
        description: 'Quanto a conversa JÁ atende ao critério do PRÓXIMO estágio do funil (não do atual).'
      },
      intent: {
        type: 'string',
        enum: %w[baixa media alta],
        description: 'Intenção do cliente de avançar (pediu preço, prazo, link, documento).'
      },
      urgency: {
        type: 'string',
        enum: %w[nenhuma futura proxima imediata],
        description: 'Urgência pela DATA citada na conversa (embarque, vencimento, consulta): "futura" = meses, "imediata" = dias.'
      },
      decision_maker: { type: 'string', enum: %w[desconhecido nao sim], description: 'A pessoa na conversa decide a contratação.' },
      blocker: {
        type: 'string',
        enum: %w[nenhum leve forte negativo_explicito],
        description: 'Objeção aberta: "leve" = vou pensar; "forte" = recusa, concorrente, fora de escopo; ' \
                     '"negativo_explicito" = não há negócio com esta conversa: número errado, "não é comigo"/pessoa ' \
                     'errada, pediu para parar de receber mensagens, ou é mensagem automática sem pessoa do outro ' \
                     'lado (newsletter, propaganda, aviso de sistema). Em dúvida entre "forte" e ' \
                     '"negativo_explicito", use "forte".'
      },
      ready_to_close: {
        type: 'string',
        enum: %w[nao_se_aplica falta_dado_nosso falta_dado_do_cliente],
        description: 'O cliente JÁ escolheu ou aceitou (plano, proposta, horário) e só falta UM dado para emitir ou ' \
                     'fechar: "falta_dado_nosso" quando a pendência é nossa (link, boleto, apólice, confirmação); ' \
                     '"falta_dado_do_cliente" quando é dele (documento, CPF, data). "nao_se_aplica" em todo o resto, ' \
                     'inclusive quando ainda está escolhendo, negociando ou já fechou.'
      },
      buying_signal: {
        type: 'boolean',
        description: 'true quando o cliente pediu algo concreto para fechar (preço, valor total, parcelamento, prazo, ' \
                     'link de pagamento, envio de documento) E esse pedido segue de pé. Vale também quando está IMPLÍCITO: ' \
                     'cliente recebeu preço/proposta e seguiu conversando — reclamar do valor é negociação, não desistência. ' \
                     '("vou pensar", "depois te falo") MANTÉM o sinal. Recuo explícito ("não quero mais", "desisti", ' \
                     '"fechei com outro", "não é para mim") ZERA o sinal — use blocker=forte nesse caso.'
      },
      awaiting_our_reply: {
        type: 'boolean',
        description: 'Olhe só a ÚLTIMA fala do CLIENTE. true quando ela pergunta, pede, aceita ou entrega algo que precisa ' \
                     'de resposta nossa. false quando ela não pede nada: agradecimento, confirmação, despedida, "vou pensar", ' \
                     '"vou comparar", "volto depois", ou assunto fora do negócio deste funil. Não depende dos outros sinais.'
      },
      unfulfilled_promise: {
        type: 'boolean',
        description: 'true SOMENTE quando NÓS prometemos uma ação concreta (enviar link/proposta, retornar, verificar) e ela ' \
                     'segue NÃO ENTREGUE até a última mensagem. É false quando: a promessa foi cumprida depois na própria ' \
                     'conversa ("vou gerar agora" seguido da cotação enviada); a continuação depende de dado que o CLIENTE ' \
                     'ainda não mandou (idades, documentos, CNPJ — a pendência é dele); ou a pergunta do cliente foi ' \
                     'respondida, mesmo que negativamente. Aguardar resposta DO CLIENTE a algo já entregue NUNCA é ' \
                     'promessa nossa. Em dúvida, false.'
      },
      unreadable: { type: 'boolean', description: 'true quando não há conteúdo legível (áudio sem transcrição, mensagens vazias).' },
      reason: { type: 'string', maxLength: 140, description: 'Motivo em uma linha, exibido no card. Concreto, sem adjetivo vazio.' },
      evidence: { type: 'string', maxLength: 300, description: 'Trecho curto da conversa que sustenta os sinais.' }
    },
    required: %w[next_stage_readiness intent urgency decision_maker blocker ready_to_close buying_signal
                 awaiting_our_reply unfulfilled_promise unreadable reason evidence],
    additionalProperties: false
  }.freeze
end
