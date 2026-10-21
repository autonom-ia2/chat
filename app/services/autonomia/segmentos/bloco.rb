# frozen_string_literal: true

# O bloco de segmento (tema 8, #1429; épico #1545): o texto que os agentes de IA recebem como DADO sobre o ramo do
# negócio. Quem monta o pedido (Builder e PromptBuilder, via PromptParts) põe a moldura de dado e decide onde ele entra;
# aqui mora só o conteúdo.
#
# CONTRATO:
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
# O conteúdo (#1802, lote 6) mora em config/agentes_por_pacote/seguros/<tipo>/agentes.md, um texto por tipo de conta de
# seguros, lido uma vez no boot. Segmento sem arquivo devolve nil.
#
# MARCA DE BASE (#1429): o agente nasce com `config['base'] = { segmento, versao, texto }` (os valores vigentes) e recebe
# sempre o texto GRAVADO, nunca o daqui: nem a troca de tipo da conta nem uma edição deste texto muda agente existente;
# só o botão "Atualizar com a nova base".
module Autonomia::Segmentos::Bloco
  # Teto do texto de um segmento, em bytes. O spec do bloco garante que cada texto cabe.
  TEXTO_DA_BASE_MAX = 8 * 1024

  PASTA = Rails.root.join('config/agentes_por_pacote')
  ARQUIVO = 'agentes.md'

  TEXTOS = Dir.glob(PASTA.join('*', '*', ARQUIVO).to_s).to_h do |arquivo|
    [Pathname(arquivo).dirname.relative_path_from(PASTA).to_s.freeze, File.read(arquivo).strip.freeze]
  end.freeze

  VERSOES = TEXTOS.transform_values { |texto| Digest::SHA256.hexdigest(texto)[0, 12].freeze }.freeze

  module_function

  def segmento(account)
    Autonomia::Segmentos::Pacotes.camadas(account).last
  end

  def for_segmento(segmento)
    TEXTOS[segmento]
  end

  def versao(segmento)
    VERSOES[segmento]
  end
end
