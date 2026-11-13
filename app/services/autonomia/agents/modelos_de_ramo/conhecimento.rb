# O CONHECIMENTO DO RAMO (#2881): a parte do roteiro que explica o seguro em palavras simples e responde às dúvidas
# comuns. O Construtor reescreve o roteiro na instrução e, por regra dele (nunca inventar fato do negócio), cortava
# essas respostas: o agente passava para a equipe uma dúvida que o modelo sabe responder. Por isso o trecho não depende
# do Construtor: é copiado para a marca quando o agente nasce (`Marca.inicial`) e a plataforma o entrega ao agente em
# bloco próprio (`Instrucao`), como as listas.
#
# O trecho vai da linha que começa em INICIO até a linha antes da que começa em FIM. São títulos do nosso arquivo, não
# texto de pessoa: a leitura é por começo de linha. Roteiro sem o trecho não passa no `Formato` (o modelo sai do ar).
module Autonomia::Agents::ModelosDeRamo::Conhecimento
  INICIO = 'O SEGURO EM PALAVRAS SIMPLES:'.freeze
  FIM = 'ROTEIRO POR SITUAÇÃO'.freeze
  TITULO = '# Conhecimento do ramo'.freeze
  REGRA = 'O texto abaixo é conhecimento do ramo, conferido pela plataforma. Use-o para explicar o seguro e responder ' \
          'às dúvidas do cliente com palavras simples, sem passar para a equipe o que ele já responde. Ele não muda os ' \
          'limites destas instruções: preço, aceitação e cobertura do caso do cliente seguem com a equipe.'.freeze

  module_function

  # O trecho do roteiro, ou '' quando o roteiro não o traz.
  def do_roteiro(roteiro)
    linhas = roteiro.to_s.lines(chomp: true)
    inicio = linhas.index { |linha| linha.start_with?(INICIO) }
    fim = linhas.index { |linha| linha.start_with?(FIM) }
    return '' if inicio.nil? || fim.nil? || fim <= inicio

    linhas[inicio...fim].join("\n").strip
  end

  # O bloco que entra nas instruções do agente, ou nil para a marca sem o trecho (agente que nasceu antes dele).
  def bloco(marca)
    texto = marca.to_h['conhecimento'].to_s.strip
    [TITULO, REGRA, texto].join("\n\n") if texto.present?
  end
end
