# O passo "decidir" (#2500 F7): a IA escolhe um dos caminhos, ou "nenhum se aplica" quando a conversa não deixa claro,
# em vez de chutar (F7.1). A resposta é presa às chaves dos caminhos mais `nenhum`.
#
# O "por quê" (D3 A) vira uma nota privada curta na conversa: quem não vê a conversa não vê o motivo, e o registro guarda
# só o caminho e o id da nota. Quem cria a nota é o executor, depois de gravar o registro com o caminho (`anotar`): se a
# nota falhar, a automação segue pelo caminho e o registro diz `nota_faltou`.
class Autonomia::Automacao::PassoDeDecidir
  include ::Autonomia::Automacao::ComIa

  MODELO = ::Crm::Ai::Config::MODEL_CLASSIFY
  MAX_MOTIVO = 200
  INSTRUCOES = <<~TEXTO.freeze
    Responda à pergunta de quem montou a automação escolhendo um dos caminhos pela conversa. Responda só com JSON no schema.
    "caminho": a chave de um dos caminhos. Escolha "nenhum" quando a conversa não deixar claro qual caminho vale, ou quando nenhum se aplicar: um caminho errado é pior que nenhum.
    "motivo": por que, em uma frase curta, em português.
  TEXTO

  def self.fala_com_gente?(_passo) = false

  def executar
    negado = impedido
    return negado if negado

    estado = leitura
    return Resultado.new(tipo: :ok, dados: { 'ramo' => nenhum, 'sem_leitura' => true }) if estado.vazio?

    resposta, custo = perguntar(modelo: MODELO, instrucoes: instrucoes, entrada: { conversa: estado.conversa }, schema: schema)
    @motivo = resposta['motivo'].to_s.squish.first(MAX_MOTIVO)
    Resultado.new(tipo: :ok, dados: { 'ramo' => resposta['caminho'], 'ia' => custo })
  rescue Falha => e
    falhou(e)
  end

  # A nota do motivo, no caminho escolhido. nil quando não houve pergunta à IA.
  def anotar(ramo)
    return if @motivo.nil?

    nome = Array(@passo['caminhos']).find { |caminho| caminho['chave'] == ramo }&.dig('nome') || frase(:nenhum)
    nota(frase(:decidiu, nome: nome, motivo: @motivo))
  end

  private

  def nenhum = ::Autonomia::Automacao::Receita::NENHUM

  def chaves = Array(@passo['caminhos']).pluck('chave')

  def instrucoes
    caminhos = Array(@passo['caminhos']).map { |caminho| "- #{caminho['chave']}: #{caminho['descricao']}" }
    [INSTRUCOES, "Pergunta: #{@passo['pergunta']}", "Caminhos:\n#{caminhos.join("\n")}\n- #{nenhum}: nenhum se aplica"].join("\n\n")
  end

  def schema
    { name: 'automacao_decidir',
      schema: { type: 'object', additionalProperties: false, required: %w[caminho motivo],
                properties: { caminho: { type: 'string', enum: chaves + [nenhum] }, motivo: { type: 'string' } } } }
  end
end
