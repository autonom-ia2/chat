# A proposta da renovação do seguro (E8, #2901): o PDF da proposta no topo (DOCUMENT) e o texto que diz o que é. Sai pela
# caixa do WhatsApp oficial que a corretora escolheu, sozinha (`quem_envia = sozinho`) ou no clique de "Enviar" no card
# (Carteira::Cotacao::Proposta). O arquivo do envio é a proposta guardada na conversa, com o nome
# "Proposta de renovação.pdf" (`HeaderMedia.dispatch_file`); o exemplo que a Meta analisa é fictício
# (`Garantir::TOPOS_DE_EXEMPLO`).
#
# Redação de UTILIDADE: fala da renovação do seguro que a pessoa já tem e do próximo passo, sem preço, desconto nem
# urgência no texto (o valor está no PDF). A variável nunca abre nem fecha o corpo.
module Whatsapp::Templates::Finalidades::RenovacaoProposta
  FINALIDADES = {
    'renovacao_proposta' => {
      dono: 'carteira', opcoes: [],
      variantes: {
        [] => {
          nome: 'renovacao_proposta_v1', amigavel: 'Renovação: proposta', topo: 'DOCUMENT',
          campos: %w[cliente.primeiro_nome],
          texto: 'Olá, {{1}}! Segue a proposta de renovação do seu seguro, no arquivo acima. Se quiser renovar ou tiver ' \
                 'alguma dúvida, é só responder esta mensagem.'
        }
      }
    }
  }.freeze
end
