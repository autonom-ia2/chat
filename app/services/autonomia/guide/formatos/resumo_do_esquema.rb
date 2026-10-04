# O esquema de um campo JSON em texto curto, para o modelo (#932).
#
# No resumo da ação vai só o primeiro nível: os valores fechados de cada chave e o aviso de que cada
# ramo tem regra própria. O ramo inteiro (o `action_params` de uma ação, o `action_config` de um tipo
# de passo) vem quando o Guia pede `formato_da_acao` com `campo: "actions.send_email_to_team"`.
class Autonomia::Guide::Formatos::ResumoDoEsquema
  Esquemas = ::Autonomia::Guide::Formatos::Esquemas

  def initialize(caminho, esquema)
    @caminho = caminho
    @esquema = esquema
  end

  # As linhas de dentro do campo, no resumo da ação.
  def linhas(limite)
    [*valores_fechados(limite), *ramos_em_linha]
  end

  # O campo inteiro: o que ele é, as chaves com valores fechados e o que cada ramo faz.
  def texto(teto)
    linhas = ["Campo #{@caminho}:", @esquema['description'], *valores_fechados(nil), *ramos_descritos].compact
    passa = linhas.each_index.find { |indice| linhas[0..indice].join("\n").size > teto }
    return linhas.join("\n") unless passa

    (linhas[0...(passa - 1)] + ["(mais #{linhas.size - passa + 1} linhas cortadas pelo limite de tamanho)"]).join("\n")
  end

  # Só o ramo pedido ('send_email_to_team'), com a descrição do que o motor faz. Nil se não há.
  def ramo(nome, teto)
    achado = Esquemas.ramo(@esquema, nome)
    return unless achado

    campo, = Esquemas.do_ramo(achado)
    "Campo #{@caminho}.#{nome} (#{campo} = #{nome}):\n#{JSON.pretty_generate(achado.except('if'))}".first(teto)
  end

  private

  # O objeto que cada item é (lista de objetos) ou o próprio objeto.
  def alvo
    @esquema['type'] == 'array' && @esquema['items'].is_a?(Hash) ? @esquema['items'] : @esquema
  end

  def valores_fechados(limite)
    (alvo['properties'] || {}).filter_map do |nome, trecho|
      valores = fechados(trecho)
      "#{nome}: um de: #{listar(valores, limite)}#{da_conta(trecho)}" if valores.any?
    end
  end

  def listar(valores, limite)
    mostrados = limite ? valores.first(limite) : valores
    sobra = valores.size > mostrados.size ? " e mais #{valores.size - mostrados.size}" : ''
    "#{mostrados.map { |valor| valor.is_a?(String) && valor.present? ? valor : valor.to_json }.join(', ')}#{sobra}"
  end

  def fechados(trecho)
    [trecho, *Array(trecho['anyOf'])].flat_map { |opcao| Array(opcao['enum']) + Array(opcao.slice('const').values) }.uniq
  end

  # A opção que é um registro da conta (atributo personalizado), dita junto dos valores fechados.
  def da_conta(trecho)
    opcao = Array(trecho['anyOf']).find { |item| item['x-da-conta'] }
    opcao ? "; ou #{opcao['description'] || opcao.dig('x-da-conta', 'modelo')}" : ''
  end

  def ramos_por_campo
    Esquemas.ramos(@esquema).group_by { |_valor, ramo| Esquemas.do_ramo(ramo).first }
  end

  def ramos_em_linha
    ramos_por_campo.keys.map do |campo|
      "cada #{campo} tem regra própria: peça formato_da_acao com campo \"#{@caminho}.<#{campo}>\" antes de montar"
    end
  end

  def ramos_descritos
    ramos_por_campo.flat_map do |campo, ramos|
      ["Por #{campo} (peça campo \"#{@caminho}.<#{campo}>\" para o detalhe):",
       *ramos.map { |valor, ramo| "- #{valor}: #{ramo['description']}#{' (sem volta: pede confirmação)' if ramo['x-sem-volta']}" }]
    end
  end
end
