# "Algo mudou?" da renovação do seguro (E8, #2901): o primeiro contato antes de cotar a renovação, que sai sozinho pela
# caixa do WhatsApp oficial que a corretora escolheu (Carteira::Cotacao::AlgoMudou). Dois botões de resposta rápida:
# "Nada mudou" (payload `renovacao_nada_mudou`) e "Mudou algo" (`renovacao_mudou`); a resposta é casada pelo payload e
# pela mensagem citada (Carteira::CotacaoRespostaListener), nunca pelo texto.
#
# Redação de UTILIDADE: fala do seguro que a pessoa já tem e do próximo passo, sem oferta, preço ou urgência. A variável
# nunca abre nem fecha o corpo. `negocio.prazo` é a data esperada do card de renovação: o fim da vigência.
# Modelo novo = nome novo (`_v2`); este nome e este texto são o contrato com a Meta depois de aprovado.
module Whatsapp::Templates::Finalidades::RenovacaoAlgoMudou
  NADA_MUDOU = 'renovacao_nada_mudou'.freeze
  MUDOU = 'renovacao_mudou'.freeze

  FINALIDADES = {
    'renovacao_algo_mudou' => {
      dono: 'carteira', opcoes: [],
      variantes: {
        [] => {
          nome: 'renovacao_algo_mudou_v1', amigavel: 'Renovação: algo mudou?',
          campos: %w[cliente.primeiro_nome negocio.prazo],
          texto: 'Olá, {{1}}! O seu seguro termina em {{2}} e já estamos cuidando da renovação. Desde a última contratação, ' \
                 'mudou alguma coisa, como endereço, veículo ou quem usa? Toque em uma das opções abaixo.',
          botoes: [
            { tipo: 'quick_reply', texto: 'Nada mudou', payload: NADA_MUDOU }.freeze,
            { tipo: 'quick_reply', texto: 'Mudou algo', payload: MUDOU }.freeze
          ].freeze
        }
      }
    }
  }.freeze
end
