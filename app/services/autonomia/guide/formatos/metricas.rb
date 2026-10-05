# As duas medidas da cobertura por dentro (#932), contadas uma vez por action do controller (o PATCH
# e o PUT da mesma rota são a mesma leitura):
#
# - campos aninhados com vocabulário: campo de objeto ou lista de objetos cuja regra interna o
#   formato traz (`esquema`), de todos os campos aninhados;
# - leituras cruas tipadas: `params[:x]` sem coluna que diga o tipo, tipado pelo uso no código ou pelo
#   nome (`tipo_pela_leitura`), de todas as leituras cruas. As que sobram vão listadas com o motivo.
class Autonomia::Guide::Formatos::Metricas
  ANINHADOS = %w[objeto lista_de_objetos objeto_livre json].freeze
  SEM_TIPO = 'leitura crua sem tipo: '.freeze
  SEM_MOTIVO = 'o código não converte nem compara o valor'.freeze

  def initialize(formatos)
    @formatos = formatos
  end

  def aninhados
    campos.select { |_chave, campo| ANINHADOS.include?(campo['tipo']) }
  end

  def com_esquema
    aninhados.count { |_chave, campo| campo['esquema'] }
  end

  def tipadas
    campos.count { |_chave, campo| campo['tipo_pela_leitura'] }
  end

  # [controller, campo, motivo] de cada leitura crua que ficou sem tipo.
  def sem_tipo_lista
    @sem_tipo_lista ||= @formatos.values.flat_map do |formato|
      Array(formato['motivos']).select { |motivo| motivo.start_with?(SEM_TIPO) }.flat_map do |motivo|
        motivo.delete_prefix(SEM_TIPO).split(', ').map { |item| [formato['controller'], *campo_e_motivo(item)] }
      end
    end.uniq.sort
  end

  def texto
    lidas = tipadas + sem_tipo_lista.size
    <<~TEXTO
      ## Por dentro dos campos

      | | Total |
      |---|---|
      | Campos aninhados com vocabulário | #{com_esquema} de #{aninhados.size} |
      | Leituras cruas tipadas | #{tipadas} de #{lidas} |
    TEXTO
  end

  def sem_tipo
    linhas = sem_tipo_lista.map { |controller, campo, motivo| "- `#{controller}` #{campo} — #{motivo}" }
    "## Leituras cruas sem tipo\n\n#{linhas.join("\n")}\n"
  end

  private

  # Cada campo, uma vez por action do controller e caminho.
  def campos
    @campos ||= @formatos.values.each_with_object({}) do |formato, todos|
      juntar(todos, formato['controller'], (formato['campos'] || {}).merge(formato['fora_do_envelope'] || {}), nil)
    end
  end

  def juntar(todos, controller, campos, prefixo)
    campos.each do |nome, campo|
      caminho = [prefixo, nome].compact.join('.')
      todos["#{controller} #{caminho}"] ||= campo
      juntar(todos, controller, campo['campos'] || {}, caminho)
    end
  end

  # 'x (repassada a Y)' → ['x', 'repassada a Y']
  def campo_e_motivo(item)
    campo, motivo = item.split(' (', 2)
    [campo, motivo ? motivo.delete_suffix(')') : SEM_MOTIVO]
  end
end
