# Cobrança (`cobranca_vencimento`, #1498): um modelo por momento (antes, no dia, depois do vencimento) e por valor (com
# ou sem). O momento é texto fixo, não variável: é o texto fixo que a Meta aprova. Sem "negócio" nem "compra" no texto.
# Em produção desde o #1535: nome e texto não mudam (modelo novo = nome novo, `_v2`).
module Whatsapp::Templates::Finalidades::Cobranca
  FIM = 'Se o pagamento já foi feito, por favor desconsidere esta mensagem.'.freeze
  DEPOIS_FIM = "Se precisar de ajuda com o pagamento, é só responder esta mensagem. #{FIM}".freeze
  COM_VALOR = %w[cliente.primeiro_nome negocio.valor negocio.titulo negocio.prazo].freeze
  SEM_VALOR = %w[cliente.primeiro_nome negocio.titulo negocio.prazo].freeze

  FINALIDADES = {
    'cobranca_vencimento' => {
      dono: 'cobranca',
      opcoes: %i[momento com_valor],
      variantes: {
        ['antes', true] => { nome: 'cobranca_antes_vencimento_com_valor_v1', amigavel: 'Cobrança: antes do vencimento (com valor)',
                             campos: COM_VALOR,
                             texto: 'Olá, {{1}}! Passando para lembrar que o seu pagamento de {{2}} referente a {{3}} vence em ' \
                                    "{{4}}. #{FIM}" },
        ['antes', false] => { nome: 'cobranca_antes_vencimento_sem_valor_v1', amigavel: 'Cobrança: antes do vencimento',
                              campos: SEM_VALOR,
                              texto: "Olá, {{1}}! Passando para lembrar que o seu pagamento referente a {{2}} vence em {{3}}. #{FIM}" },
        ['no_dia', true] => { nome: 'cobranca_dia_vencimento_com_valor_v1', amigavel: 'Cobrança: no dia do vencimento (com valor)',
                              campos: COM_VALOR,
                              texto: "Olá, {{1}}! O seu pagamento de {{2}} referente a {{3}} vence hoje, {{4}}. #{FIM}" },
        ['no_dia', false] => { nome: 'cobranca_dia_vencimento_sem_valor_v1', amigavel: 'Cobrança: no dia do vencimento',
                               campos: SEM_VALOR,
                               texto: "Olá, {{1}}! O seu pagamento referente a {{2}} vence hoje, {{3}}. #{FIM}" },
        ['depois', true] => { nome: 'cobranca_apos_vencimento_com_valor_v1', amigavel: 'Cobrança: depois do vencimento (com valor)',
                              campos: COM_VALOR,
                              texto: 'Olá, {{1}}! O seu pagamento de {{2}} referente a {{3}} venceu em {{4}} e ainda não consta ' \
                                     "como pago. #{DEPOIS_FIM}" },
        ['depois', false] => { nome: 'cobranca_apos_vencimento_sem_valor_v1', amigavel: 'Cobrança: depois do vencimento',
                               campos: SEM_VALOR,
                               texto: 'Olá, {{1}}! O seu pagamento referente a {{2}} venceu em {{3}} e ainda não consta como ' \
                                      "pago. #{DEPOIS_FIM}" }
      }
    }
  }.freeze
end
