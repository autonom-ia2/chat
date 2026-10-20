# frozen_string_literal: true

# O bloco de segmento da conta (tema 8, #1429; épico #1545): o texto que os agentes de IA recebem como DADO sobre o
# ramo do negócio. Quem monta o pedido (Builder e PromptBuilder, via PromptParts::SegmentoDaConta) põe a moldura de
# dado e decide onde ele entra; aqui mora só o conteúdo.
#
# CONTRATO (vale também quando o conteúdo entrar, no PR da Segmentação):
#   - `for(account)` devolve String ou nil. nil = a conta não tem bloco, e o pedido ao modelo fica igual ao de antes.
#   - Estável: a mesma conta, com a mesma escolha, recebe o mesmo texto em toda chamada. O bloco entra no prefixo em
#     cache do pedido; texto que varia quebra o cache por conta.
#   - Não depende de conversa: só da conta (o pacote/segmento dela). Nada de hora, contato ou mensagem.
#   - Só orientação e vocabulário do ramo. Nenhuma frase pronta de cliente: o modelo copia frase (a tabela 3B do
#     #1545 é referência e caso de eval, nunca conteúdo daqui).
#
# Por enquanto devolve nil sempre. A Segmentação preenche o conteúdo e acrescenta a checagem do interruptor
# AUTONOMIA_PACOTES_ENABLED.
#
# MARCA DE BASE (#1429): o agente guarda o segmento com que nasceu (`config['base']`) e lê o bloco por ele, nunca pela
# conta: trocar o tipo da conta não muda agente existente. Quem nasce lê `segmento` e `versao` (a versão guardada diz
# com que texto ele nasceu); quem atende lê `for_segmento` com o segmento gravado. `for(account)` fica pelo contrato
# antigo; nada novo depende dele.
module Autonomia::Segmentos::Bloco
  module_function

  def for(_account)
    nil
  end

  # O segmento da conta, fonte única: a camada mais específica do pacote ('seguros/corretora'), ou nil para conta geral
  # ou com o interruptor desligado.
  def segmento(account)
    Autonomia::Segmentos::Pacotes.camadas(account).last
  end

  # O texto do bloco de um segmento. nil por enquanto: o lote 6 da Segmentação preenche.
  def for_segmento(_segmento)
    nil
  end

  # A versão do texto de um segmento (o lote 6 preenche, SHA256[0,12]). nil por enquanto.
  def versao(_segmento)
    nil
  end
end
