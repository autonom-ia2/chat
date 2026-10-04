# O relatório de cobertura do formato das ações (#900), versionado ao lado do
# JSON. Quem revisa o PR vê, sem rodar nada, quantas ações o Guia sabe montar
# por inteiro e, pelo nome, cada uma que ainda não sabe — com o motivo.
class Autonomia::Guide::Formatos::Relatorio
  # O começo de cada motivo, para contar por categoria. A ordem é a da tabela.
  CATEGORIAS = [
    'leitura crua sem tipo',
    'aceita qualquer campo',
    'params inteiro repassado',
    'lê o corpo cru',
    'permit com valor calculado',
    'termina em código de fora do repositório',
    'a rota não tem a action',
    'controller não encontrado'
  ].freeze

  def initialize(formatos, leituras = {})
    @formatos = formatos
    @leituras = leituras
  end

  def texto
    [cabecalho, contagens, metricas.texto, por_motivo, lista, metricas.sem_tipo, leituras].join("\n")
  end

  # As duas métricas do #932: campos JSON com esquema e leituras cruas com tipo.
  def metricas
    @metricas ||= ::Autonomia::Guide::Formatos::Metricas.new(@formatos)
  end

  private

  def com_corpo
    @com_corpo ||= @formatos.reject { |_acao, formato| formato['sem_corpo'] }
  end

  def incompletas
    @incompletas ||= com_corpo.reject { |_acao, formato| formato['completo'] }
  end

  def cabecalho
    <<~TEXTO
      # Formato das ações do Guia — cobertura

      Gerado por `bundle exec rails autonomia:guia:formatos` a partir do código (#900). Não edite à mão.
      "Completa" quer dizer que o nome de todo campo aceito saiu do código com segurança.
    TEXTO
  end

  def contagens
    completas = com_corpo.size - incompletas.size
    <<~TEXTO
      | | Ações |
      |---|---|
      | No catálogo | #{@formatos.size} |
      | Sem corpo | #{@formatos.size - com_corpo.size} |
      | Com corpo | #{com_corpo.size} |
      | Com corpo e formato completo | #{completas} (#{percentual(completas, com_corpo.size)}) |
      | Com corpo e formato incompleto | #{incompletas.size} |
    TEXTO
  end

  def por_motivo
    linhas = CATEGORIAS.filter_map do |categoria|
      total = incompletas.count { |_acao, formato| Array(formato['motivos']).any? { |motivo| motivo.start_with?(categoria) } }
      "| #{categoria} | #{total} |" if total.positive?
    end
    "## Incompletas por motivo\n\nUma ação pode ter mais de um motivo.\n\n| Motivo | Ações |\n|---|---|\n#{linhas.join("\n")}\n"
  end

  def lista
    linhas = incompletas.sort.map { |acao, formato| "- `#{acao}` — #{Array(formato['motivos']).join('; ')}" }
    "## Ações incompletas\n\n#{linhas.join("\n")}\n"
  end

  # As leituras (#942): a que tem a lista de parâmetros recusa o que não está nela; a que não tem não
  # recusa nada.
  def leituras
    sem_lista = @leituras.reject { |_recurso, leitura| leitura.key?('parametros') }
    linhas = sem_lista.sort.map { |recurso, leitura| "- `GET #{recurso}` — #{Array(leitura['motivos']).join('; ')}" }
    <<~TEXTO
      ## Parâmetros das leituras

      O Guia recusa parâmetro que a leitura não lê. Leitura sem lista conhecida não recusa nada.

      | | Leituras |
      |---|---|
      | No catálogo | #{@leituras.size} |
      | Com parâmetros conhecidos | #{@leituras.size - sem_lista.size} |
      | Sem parâmetros conhecidos | #{sem_lista.size} |

      ### Leituras sem parâmetros conhecidos

      #{linhas.join("\n")}
    TEXTO
  end

  def percentual(parte, todo)
    return '0%' if todo.zero?

    "#{format('%.1f', 100.0 * parte / todo).tr('.', ',')}%"
  end
end
