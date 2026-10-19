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
# O conteúdo mora em config/agentes_por_pacote/seguros/<tipo>/agentes.md, um texto por tipo de conta de seguros, lido uma vez no
# boot. Vale só com o interruptor AUTONOMIA_PACOTES_ENABLED ligado e conta de seguros (as camadas de
# Autonomia::Segmentos::Pacotes); conta geral, interruptor desligado ou tipo sem arquivo devolve nil.
module Autonomia::Segmentos::Bloco
  PASTA = Rails.root.join('config/agentes_por_pacote')
  ARQUIVO = 'agentes.md'

  TEXTOS = Dir.glob(PASTA.join('*', '*', ARQUIVO).to_s).to_h do |arquivo|
    [Pathname(arquivo).dirname.relative_path_from(PASTA).to_s.freeze, File.read(arquivo).strip.freeze]
  end.freeze

  module_function

  def for(account)
    camada = Autonomia::Segmentos::Pacotes.camadas(account).last
    camada && TEXTOS[camada]
  end
end
