# Varredura de legado dos esquemas JSON (#932, AC-G5). SÓ LEITURA.
#
#   bundle exec rails runner script/guia/varredura_esquemas.rb                    # AutomationRule Macro Crm::StageAutomationStep
#   bundle exec rails runner script/guia/varredura_esquemas.rb AutomationRule     # um modelo só
#
# Para cada registro, confere cada coluna que tem `validates :col, json_schema:` contra o esquema,
# como o validador faria, mas sem `valid?` nem `save`: nenhum callback roda e nada é gravado. Imprime
# só contagens — por modelo, por conta, por tipo de erro e por ponteiro (índices viram *). Nenhum
# valor da coluna sai: nem texto, nem e-mail, nem URL. Sequência longa de letras e números (token)
# vira <REDACTED> mesmo no ponteiro.
#
# O resultado decide o merge: registro de produção que deixaria de salvar pede um ramo `deprecated`
# no esquema antes. Rodar em produção só com o OK do Rodrigo, e registrar a saída em docs/audit/.
class VarreduraEsquemas
  PADRAO = %w[AutomationRule Macro Crm::StageAutomationStep].freeze
  SEGREDO = /[A-Za-z0-9_\-]{32,}/

  def initialize(modelos = PADRAO)
    @modelos = (modelos.presence || PADRAO).map(&:constantize)
    @totais = Hash.new(0)
    @por_conta = Hash.new(0)
    @por_erro = Hash.new(0)
    @por_ponteiro = Hash.new(0)
  end

  def varrer
    @modelos.each { |modelo| colunas(modelo).each { |coluna, validador| varrer_coluna(modelo, coluna, validador) } }
    self
  end

  def relatorio
    [
      '# Varredura dos esquemas JSON (só leitura)',
      secao('Registros conferidos e recusados, por coluna', @totais),
      secao('Recusados por conta (account_id)', @por_conta),
      secao('Erros por tipo e lugar no esquema', @por_erro),
      secao('Erros por ponteiro no dado', @por_ponteiro)
    ].join("\n\n")
  end

  private

  def colunas(modelo)
    modelo.validators.grep(JsonSchemaValidator).flat_map { |validador| validador.attributes.map { |coluna| [coluna.to_s, validador] } }
  end

  def varrer_coluna(modelo, coluna, validador)
    nome = "#{modelo.name}##{coluna}"
    modelo.find_each do |registro|
      @totais["#{nome} conferidos"] += 1
      erros = conferir(registro, coluna, validador)
      next if erros.empty?

      contar(nome, registro, erros)
    end
  end

  def conferir(registro, coluna, validador)
    JSONSchemer.schema(validador.esquema(registro), formats: JsonSchemaFormatos::TODOS)
               .validate(JSON.parse(registro[coluna].to_json)).to_a
  end

  def contar(nome, registro, erros)
    @totais["#{nome} recusados"] += 1
    @por_conta["#{nome} conta #{registro.try(:account_id) || '-'}"] += 1
    erros.each do |erro|
      @por_erro[limpo("#{nome} #{erro['type']} em #{erro['schema_pointer']}")] += 1
      @por_ponteiro[limpo("#{nome} #{generico(erro['data_pointer'])}")] += 1
    end
  end

  # /0/action_params/3 → /*/action_params/*: conta o lugar, não o registro.
  def generico(ponteiro)
    ponteiro.to_s.split('/').map { |parte| Integer(parte, exception: false) ? '*' : parte }.join('/')
  end

  def limpo(texto)
    texto.gsub(SEGREDO, '<REDACTED>')
  end

  def secao(titulo, contagem)
    linhas = contagem.sort_by { |chave, total| [-total, chave] }.map { |chave, total| "- #{chave}: #{total}" }
    "## #{titulo}\n\n#{linhas.presence&.join("\n") || '- nenhum'}"
  end
end

# Pelo `rails runner` roda; carregado pelo spec, só define a classe.
puts VarreduraEsquemas.new(ARGV).varrer.relatorio if $PROGRAM_NAME == __FILE__
