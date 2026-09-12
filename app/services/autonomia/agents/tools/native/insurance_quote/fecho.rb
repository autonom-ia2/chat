# O QUE A COTAÇÃO ENTREGA — E O QUE ELA AFIRMA — QUANDO A EXECUÇÃO ACABA SEM FECHAR (entrega 4, e as
# rodadas 5 e 6 da entrega 8).
#
# Três respostas ao `Tools::Encerramento`, e nenhuma delas é do motor: o que ainda vale entregar, se
# o cliente já tem RESULTADO em mãos e se SOBROU alguma coisa. As duas últimas decidem entre a frase
# parcial e o silêncio, e só a ferramenta sabe respondê-las — `delivered_count` conta qualquer item
# aceito para publicação, inclusive a pergunta pelo dado que falta.
#
# Separado da ferramenta pelo mesmo motivo de `Comparativo`, `Declaracao`, `Recusas`, `Envio` e
# `Veiculo`: é outro assunto, e a classe está no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Fecho
  extend ActiveSupport::Concern

  # O COMPARATIVO NÃO PODE SER REFÉM DA SEGURADORA MAIS LENTA. Ele era gerado só no ramo `done`,
  # quando o portal marcava a cotação como `completed` — e em 08/09/2026 a execução entregou cinco
  # preços e estourou o prazo na 22ª consulta, então o PDF nunca saiu. O comparativo é o que o
  # cliente leva para decidir; os preços soltos no chat são o resumo dele.
  #
  # MAS ELE É TRABALHO NOVO NO PORTAL (rodada 6, P2-E): `comparison_pdf` faz login e uma chamada de
  # até 60 s, e o publicador ainda baixa o arquivo. No caminho do VARREDOR isso não sai — lá são até
  # 500 linhas em sequência dentro de um cron, com 25 s de shutdown do Sidekiq, e quem é morto no
  # meio deixa a linha em curso com a marca `closed` e sem fecho, para sempre. O cliente fica com os
  # preços que já leu e com o fecho honesto sobre o que ele tem; o PDF do portal continua lá.
  def closing_deliveries(handle, trabalho_novo: true)
    return [] unless trabalho_novo

    [comparison_pdf(handle.to_h)].compact
  end

  # RESULTADO DA COTAÇÃO É PREÇO PUBLICADO (rodada 6, P1-B): a lista sob `DELIVERED_KEY`, que só
  # recebe quem COTOU. Nunca o `pedido` — a pergunta pelo dado que falta também é uma entrega aceita
  # (`poll` a devolve, e `delivered_count` a conta), e era por ela que uma cotação que só perguntou
  # dados fechava dizendo "o que chegou está aqui em cima" sem nada em cima.
  #
  # (`self.class::` porque o nome curto não se resolve dentro de um módulo compacto — o mesmo
  # cuidado de `Comparativo`.)
  def resultado_entregue?(handle)
    Array(handle.to_h[self.class::DELIVERED_KEY]).any?
  end

  # SEMPRE SOBRA, POR CONSTRUÇÃO. O encerramento só existe nos caminhos em que a cotação NÃO fechou
  # no portal — `AsyncRunJob#fail_run` (prazo, tentativas, ferramenta ou agente fora) e o varredor.
  # A que fecha vai por `finish_done`, que não passa por aqui. Cotação interrompida é cotação com
  # consulta pendente, que é exatamente o que a frase parcial diz ao cliente.
  def resta_entregar?(_handle)
    true
  end
end
