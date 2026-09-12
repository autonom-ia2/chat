# O QUE A COTAÇÃO ENTREGA — E O QUE ELA AFIRMA — QUANDO A EXECUÇÃO ACABA SEM FECHAR (entregas 4 e 8).
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
  # MAS ELE É TRABALHO NOVO NO PORTAL: `comparison_pdf` faz login e uma chamada de
  # até 60 s, e o publicador ainda baixa o arquivo. No caminho do VARREDOR isso não sai — lá são até
  # 500 linhas em sequência dentro de um cron, com 25 s de shutdown do Sidekiq, e quem é morto no
  # meio deixa a linha em curso com a marca `closed` e sem fecho, para sempre. O cliente fica com os
  # preços que já leu e com o fecho honesto sobre o que ele tem; o PDF do portal continua lá.
  def closing_deliveries(handle, trabalho_novo: true)
    return [] unless trabalho_novo

    [comparison_pdf(handle.to_h)].compact
  end

  # RESULTADO DA COTAÇÃO É PREÇO PUBLICADO: a lista sob `DELIVERED_KEY`, que só
  # recebe quem COTOU. Nunca o `pedido` — a pergunta pelo dado que falta também é uma entrega aceita
  # (`poll` a devolve, e `delivered_count` a conta), e era por ela que uma cotação que só perguntou
  # dados fechava dizendo "o que chegou está aqui em cima" sem nada em cima.
  #
  # (`self.class::` porque o nome curto não se resolve dentro de um módulo compacto — o mesmo
  # cuidado de `Comparativo`.)
  def resultado_entregue?(handle)
    Array(handle.to_h[self.class::DELIVERED_KEY]).any?
  end

  # SOBRA ENQUANTO O PORTAL NÃO TIVER FECHADO — e quem prova que ele fechou é `PDF_SENT_KEY`.
  #
  # "Sempre sobra, por construção" era falso, e o estado que o desmente é alcançável HOJE. A chave
  # só é gravada no ramo `done` de `build_progress` (`insurance_quote.rb`), depois do
  # `return … unless finished?(result)`: ela existir significa que o portal respondeu `completed` (ou
  # `failed`) e que o comparativo saiu. O que separa essa execução de um desfecho feliz é só o
  # `finish!('done')` que veio DEPOIS do `record_attempt!` que persistiu o handle — morto o worker
  # entre os dois, a linha fica `running` com a chave no banco e o varredor a encerra. Sem esta
  # correção, quem recebeu os preços E o comparativo lia "algumas seguradoras não responderam a
  # tempo". Frase nenhuma é melhor que frase falsa.
  #
  # `PDF_SENT_KEY` sobrevive ao corte das marcas do motor (`AsyncRunJob::MARCAS` não a lista), então
  # ela chega aqui pelo handle que o encerramento entrega.
  #
  # Ausente, não se pode afirmar que o portal fechou, e a frase parcial descreve o que o cliente tem:
  # preços na tela e consulta em aberto. (Ela só é perguntada depois de `resultado_entregue?`.)
  def resta_entregar?(handle)
    !handle.to_h[self.class::PDF_SENT_KEY]
  end
end
