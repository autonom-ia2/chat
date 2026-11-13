# O nome do dia a dia de cada dado da resposta de um "buscar em outro sistema" (#2934): o teste mostra "Status do
# pedido", nunca a chave crua do JSON ("order.status"). A pessoa troca o nome quando guarda o dado.
#
# A IA da conta sugere, só com os caminhos: os valores nunca vão, porque podem ser dado de cliente. Sem a chave de IA da
# própria conta (PassoDeIa), ou se ela falhar, o nome sai do próprio caminho: as palavras separadas, sem os números das
# listas, e a primeira maiúscula. Uma ida só, curta, por teste: o teste roda dentro do pedido da tela.
class Autonomia::Automacao::RotulosDaConsulta
  MODELO = ::Crm::Ai::Config::MODEL_CLASSIFY
  TEMPO = 8
  NOME_MAXIMO = 60
  INSTRUCOES = <<~TEXTO.freeze
    Cada item de "caminhos" é o caminho de um dado na resposta de outro sistema (o ponto entra num objeto; o número, numa
    lista). Dê a cada caminho um nome curto do dia a dia, que uma pessoa sem conhecimento técnico entenda, no idioma
    pedido em "idioma". Exemplo: pedido.status vira "Status do pedido". Até 4 palavras, sem sigla técnica. Devolva um
    item por caminho, com o caminho igual ao recebido.
  TEXTO
  SCHEMA = {
    name: 'automacao_rotulos_da_consulta',
    schema: {
      type: 'object', additionalProperties: false, required: %w[rotulos],
      properties: { rotulos: { type: 'array', items: { type: 'object', additionalProperties: false, required: %w[caminho nome],
                                                       properties: { caminho: { type: 'string' }, nome: { type: 'string' } } } } }
    }
  }.freeze

  def initialize(conta)
    @conta = conta
  end

  # { caminho => nome }
  def para(caminhos)
    sugeridos = caminhos.any? ? da_ia(caminhos) : {}
    caminhos.index_with { |caminho| sugeridos[caminho].presence || self.class.do_caminho(caminho) }
  end

  # "pedido.dataPrevista" => "Pedido data prevista"; "itens.0.nome" => "Itens nome".
  def self.do_caminho(caminho)
    palavras = caminho.to_s.split('.').reject { |parte| Integer(parte, 10, exception: false) }.flat_map { |parte| palavras_de(parte) }
    palavras.join(' ').downcase.capitalize.presence || caminho.to_s
  end

  # "dataPrevista" e "data_prevista" => ["data", "Prevista"]. Sem expressão regular: letra por letra.
  def self.palavras_de(parte)
    parte.each_char.with_object([+'']) do |letra, lista|
      if ['_', '-', ' '].include?(letra)
        lista << +''
      else
        lista << +'' if letra != letra.downcase && lista.last.present? && lista.last[-1] == lista.last[-1].downcase
        lista.last << letra
      end
    end.compact_blank
  end

  private

  def da_ia(caminhos)
    ia = ::Autonomia::Automacao::PassoDeIa.new(conta: @conta, feature: 'automacao_consultar', modelo: MODELO)
    return {} unless ia.configurada?

    resposta, = ia.perguntar(instrucoes: INSTRUCOES, entrada: { idioma: @conta.locale, caminhos: caminhos }, schema: SCHEMA, tempo: TEMPO)
    Array(resposta['rotulos']).to_h { |item| [item['caminho'], item['nome'].to_s.strip.first(NOME_MAXIMO)] }
  rescue ::Autonomia::Automacao::PassoDeIa::Falha
    {}
  end
end
