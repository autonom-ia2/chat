# A mensagem que disparou o gatilho `mensagem.criada`, para o filtro separar a do cliente da resposta da equipe e da
# nota. Só existe no filtro do gatilho; nos passos ela já passou.
#
# Saiu de `Valores`, que segue sendo a porta dos caminhos (`Valores::MENSAGEM`).
module Autonomia::Automacao::Valores::Mensagem
  VALORES = {
    'mensagem.tipo' => lambda do |mensagem|
      next 'nota' if mensagem.private?

      mensagem.incoming? ? 'recebida' : 'enviada'
    end,
    'mensagem.privada' => ->(mensagem) { mensagem.private? },
    # A mensagem é a primeira de verdade da conversa (#2527)? A nota e a atividade nunca são.
    'mensagem.primeira' => ->(mensagem) { ::Autonomia::Automacao::PrimeiraMensagem.primeira?(mensagem) },
    # A mensagem traz foto ou PDF (#2716, a régua do ex.14): FotoOuPdf. Áudio, figurinha e outro arquivo não contam.
    'mensagem.tem_anexo' => ->(mensagem) { ::Autonomia::Automacao::FotoOuPdf.mensagem?(mensagem) },
    # O nome da campanha a que o cliente responde (lote 5, #2681); vazio fora de resposta a campanha.
    'mensagem.campanha' => ->(mensagem) { ::Autonomia::Automacao::RespostaDaCampanha.titulo(mensagem) }
  }.freeze
end
