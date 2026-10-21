# frozen_string_literal: true

# O bloco de segmento (tema 8, #1429; épico #1545): o texto que os agentes de IA recebem como DADO sobre o ramo do
# negócio. Quem monta o pedido (Builder e PromptBuilder, via PromptParts) põe a moldura de dado e decide onde ele entra;
# aqui mora só o conteúdo.
#
# CONTRATO (vale também quando o conteúdo entrar, no lote 6 da Segmentação):
#   - `segmento(account)`: a camada mais específica do pacote da conta ('seguros/corretora'), ou nil para conta geral ou
#     com o interruptor AUTONOMIA_PACOTES_ENABLED desligado. Fonte única do segmento.
#   - `for_segmento(segmento)`: String ou nil. nil = o segmento não tem bloco, e o pedido ao modelo fica igual ao de
#     antes. Até TEXTO_DA_BASE_MAX bytes: acima disso o agente nasce sem texto (a marca grava nil e registra o erro).
#   - `versao(segmento)`: identifica o texto do segmento (SHA256[0,12] do texto), ou nil sem texto.
#   - Estável: o mesmo segmento devolve o mesmo texto e a mesma versão em toda chamada. Só depende do segmento: nada de
#     conta, hora, contato ou mensagem.
#   - Só orientação e vocabulário do ramo. Nenhuma frase pronta de cliente: o modelo copia frase (a tabela 3B do
#     #1545 é referência e caso de eval, nunca conteúdo daqui).
#
# Hoje `for_segmento` e `versao` devolvem nil; o lote 6 preenche.
#
# MARCA DE BASE (#1429): o agente nasce com `config['base'] = { segmento, versao, texto }` (os valores vigentes) e recebe
# sempre o texto GRAVADO, nunca o daqui: nem a troca de tipo da conta nem uma edição deste texto muda agente existente;
# só o botão "Atualizar com a nova base".
module Autonomia::Segmentos::Bloco
  # Teto do texto de um segmento, em bytes. O lote 6 garante por spec que cada texto cabe.
  TEXTO_DA_BASE_MAX = 8 * 1024

  module_function

  def segmento(account)
    Autonomia::Segmentos::Pacotes.camadas(account).last
  end

  def for_segmento(_segmento)
    nil
  end

  def versao(_segmento)
    nil
  end
end
