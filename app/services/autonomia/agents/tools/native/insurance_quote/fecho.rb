# O QUE A COTAÇÃO ENTREGA — E O QUE ELA AFIRMA — QUANDO A EXECUÇÃO ACABA SEM FECHAR (entregas 4 e 8).
#
# Três respostas ao `Tools::Encerramento`, e nenhuma delas é do motor: o que ainda vale entregar, se
# o cliente já tem RESULTADO em mãos e se SOBROU alguma coisa. As duas últimas decidem entre a frase
# parcial e o silêncio, e só a ferramenta sabe respondê-las — `delivered_count` conta qualquer item
# aceito para publicação, inclusive a pergunta pelo dado que falta.
#
# TODAS AS TRÊS DECIDEM PELO FATO, NUNCA PELA INTENÇÃO. O handle é o que esta execução TENTOU
# entregar; a mensagem na conversa é o que o cliente TEM. Os dois divergem sempre que a publicação
# volta `blocked` — e ela volta: `deliver` roda ANTES de `record_attempt!`, então uma entrega
# recusada avança o handle com os códigos das ofertas sem que mensagem nenhuma tenha entrado. Com a
# pergunta feita ao handle, o cliente que não recebeu preço nenhum lia "os preços acima são os que
# chegaram" — sem nada acima — e o motor ainda pedia ao portal um comparativo para ninguém.
#
# A pergunta do fato é `Tools::EntregaPublicada`: a passada que EMITE a entrega grava no handle o
# token dela (`PRECOS_KEY`, `COMPARATIVO_KEY`), e aqui se pergunta à conversa se esse token virou
# mensagem. O handle diz o que procurar; a conversa diz se chegou.
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
  # meio joga o resto do lote para a varredura seguinte, 10 min depois. O cliente fica com os
  # preços que já leu e com o fecho honesto sobre o que ele tem; o PDF do portal continua lá.
  #
  # E NÃO SE PEDE COMPARATIVO PARA QUEM NÃO TEM PREÇO. O comparativo é o complemento dos preços na
  # tela; sem nenhum deles ter chegado, gerá-lo é login mais uma chamada de até 60 s por uma entrega
  # que muito provavelmente será recusada pelo mesmo motivo que recusou a primeira — e o cliente
  # precisa, ali, da frase honesta de falha. A pergunta é pelo FATO: `entregues` no handle não prova
  # que preço nenhum chegou ao cliente.
  def closing_deliveries(handle, trabalho_novo: true)
    return [] unless trabalho_novo
    return [] unless resultado_entregue?(handle)

    [comparison_pdf(handle.to_h)].compact
  end

  # RESULTADO DA COTAÇÃO É PREÇO QUE VIROU MENSAGEM. Nunca o `pedido` — a pergunta pelo dado que
  # falta também é uma entrega aceita (`poll` a devolve, e `delivered_count` a conta), e era por ela
  # que uma cotação que só perguntou dados fechava dizendo "o que chegou está aqui em cima" sem nada
  # em cima. E nunca a lista de `entregues`: ela é a intenção, e avança mesmo quando a publicação é
  # recusada.
  #
  # (`self.class::` porque o nome curto não se resolve dentro de um módulo compacto — o mesmo
  # cuidado de `Comparativo`.)
  def resultado_entregue?(handle)
    Array(handle.to_h[self.class::PRECOS_KEY]).any? { |token| publicada?(token) }
  end

  # SOBRA ENQUANTO O PORTAL NÃO TIVER FECHADO — e depois dele, enquanto faltar chegar o que já foi
  # emitido.
  #
  # "Sempre sobra, por construção" era falso, e o estado que o desmente é alcançável HOJE: o
  # `finish!('done')` vem DEPOIS do `record_attempt!` que persistiu o handle, então um worker morto
  # entre os dois deixa a linha `running` com o portal já fechado, e o varredor a encerra. Quem
  # recebeu os preços E o comparativo lia "algumas seguradoras não responderam a tempo".
  #
  # QUEM PROVA QUE O PORTAL FECHOU É `FECHADO_KEY`, e não `PDF_SENT_KEY`: a segunda só é gravada
  # quando houve comparativo a emitir, e uma cotação que fecha sem URL de comparativo não a grava —
  # ler a ausência como "ainda vem coisa" é a mesma frase falsa, pela outra ponta (Codex).
  #
  # A SEGUNDA METADE é o comparativo EMITIDO que não chegou: a publicação voltou `blocked` com a
  # sentinela já gravada. Aí sobrou mesmo, e calar seria esconder do cliente que falta algo.
  # Comparativo que nunca foi emitido não é sobra: não há o que chegar.
  #
  # As duas chaves sobrevivem ao corte das marcas do motor (`AsyncRunJob::MARCAS` não as lista),
  # então chegam aqui pelo handle que o encerramento entrega.
  def resta_entregar?(handle)
    handle = handle.to_h
    !portal_fechado?(handle) || comparativo_pendente?(handle)
  end

  private

  # O portal fechou? `FECHADO_KEY` é a resposta; `PDF_SENT_KEY` vale como prova para as execuções
  # que já estavam VOANDO quando esta versão subiu — ela só é gravada no mesmo ramo `done`, depois
  # do `return … unless finished?(result)`, então quem a tem fechou. Sem esta segunda leitura, a
  # linha que atravessou o deploy com o comparativo entregue fecharia dizendo "algumas seguradoras
  # não responderam a tempo" a quem recebeu tudo — o defeito que esta entrega corrige, ressuscitado
  # pela janela do deploy.
  def portal_fechado?(handle)
    handle[self.class::FECHADO_KEY].present? || handle[self.class::PDF_SENT_KEY].present?
  end

  # O comparativo foi emitido e NÃO virou mensagem? Sem token gravado não há emissão conhecida —
  # e o que não foi emitido não está faltando.
  def comparativo_pendente?(handle)
    token = handle[self.class::COMPARATIVO_KEY]
    token.present? && !publicada?(token)
  end

  def publicada?(token)
    ::Autonomia::Agents::Tools::EntregaPublicada.publicada?(conversation, token)
  end
end
