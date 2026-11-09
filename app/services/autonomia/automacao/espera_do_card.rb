# Quem o card que mudou acorda (Lote 4, #2682): só o "esperar até" cuja condição lê um valor do card (`card.*`), no
# mesmo padrão da reunião (EsperaDaReuniao.le_reuniao?). A espera pela resposta do cliente no mesmo card não é
# reservada a cada mudança dele: com o #2710, a reunião marcada depois do ganho move o card, e isso não é resposta.
module Autonomia::Automacao::EsperaDoCard
  PREFIXO = 'card.'.freeze

  module_function

  # O passo em que a execução espera lê um valor do card? O caminho fica em `{"$valor": "..."}` dentro da condição.
  def le_o_card?(execucao)
    passo = ::Autonomia::Automacao::Roteiro.new(execucao.versao.receita).passo(execucao.cursor)
    caminhos = ::Autonomia::Automacao::EsperaDaReuniao.caminhos_da(passo.to_h['condicao'])
    caminhos.any? { |caminho| caminho.to_s.start_with?(PREFIXO) }
  end
end
