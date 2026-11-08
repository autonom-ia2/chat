# A última mensagem que a execução mandou ao cliente (Contexto#ultimo_envio, #2680), como valor da receita: o texto
# (`envio.texto`) e a situação (`envio.situacao`: saiu, entregue, lida ou falhou). Vale em qualquer alvo; antes do
# primeiro envio, lê vazio. A situação muda quando o canal confirma, e a mudança acorda o "esperar até"
# (Escuta.envio_atualizado): é o ramo "se o WhatsApp recusar, manda por e-mail o mesmo texto", sem gatilho de falha.
module Autonomia::Automacao::Envio
  SITUACOES = { 'sent' => 'saiu', 'delivered' => 'entregue', 'read' => 'lida', 'failed' => 'falhou' }.freeze

  VALORES = {
    'envio.texto' => ->(mensagem) { mensagem.content },
    'envio.situacao' => ->(mensagem) { SITUACOES[mensagem.status] }
  }.freeze
end
