# As condições da receita ao salvar (#2608, saiu da Receita): o "Só se" do gatilho, o "se" e o "esperar até". Cada
# caminho lido passa pela régua dos valores (Receita::Leitura).
class Autonomia::Automacao::Receita::Condicoes
  include ::Autonomia::Automacao::Receita::Frase

  def initialize(leitura)
    @leitura = leitura
  end

  # O caminho que não vale ali já diz o que corrigir; o valor fora só aparece depois.
  # `opcoes`: no_gatilho e na_espera, as de Receita::Leitura#problemas.
  def problemas(id, condicao, **opcoes)
    lidos = ::Autonomia::Automacao::Condicao.caminhos(condicao).flat_map { |caminho| @leitura.problemas(id, caminho, **opcoes) }
    lidos.presence || fora_do_fechado(id, condicao)
  end

  private

  # Operador ou valor que um valor fechado não tem: a condição nunca casaria.
  def fora_do_fechado(id, condicao)
    filhas = condicao.values_at('todas', 'alguma').compact.flatten
    return filhas.flat_map { |filha| fora_do_fechado(id, filha) } unless condicao.key?('campo')

    caminho = condicao.dig('campo', '$valor')
    fechado = ::Autonomia::Automacao::Valores.fechado(caminho)
    return [] unless fechado
    return [texto(:operador_fora, passo: id, caminho: caminho, operadores: fechado['operadores'].join(', '))] unless
      fechado['operadores'].include?(condicao['op'])
    return [] if fechado['opcoes'].include?(condicao['valor'])

    [texto(:valor_fora, passo: id, caminho: caminho, valor: condicao['valor'], opcoes: fechado['opcoes'].join(', '))]
  end
end
