# O formato da resposta do leitor do painel de desempenho (#2301) e a conferência do que voltou.
#
# O esquema é estrito, um objeto `{"procuras": [...]}`, como na prova cega de 27/10. As listas fechadas saem do
# catálogo da ficha (temas, marcos, resultados, motivos, regras, quem, origens e as faixas de cada corte), nunca do
# código. Os nomes dos campos são os papéis abaixo; a ficha pode trocar o nome de um papel em
# `configuracao.leitura.campos` ({papel => nome}) para casar com a chave de leitura, e acrescentar campos que a chave
# pede mas o painel não guarda em `configuracao.leitura.extras` ({nome => esquema JSON}). O campo `teste` só entra com
# `configuracao.leitura.com_teste` verdadeiro.
#
# A conferência recusa (Invalida) o que não dá para gravar: id fora do catálogo, horário que não é de uma mensagem da
# conversa, fim antes do início, lista vazia. Recusada, a conversa fica com as procuras de antes.
class Autonomia::Desempenho::LeituraAutomatica::Esquema
  class Invalida < StandardError; end

  # Os campos com papel fixo (o resto vem dos cortes e dos extras da ficha).
  PAPEIS = %w[conversa procura inicio fim teste quem pedido tema marcos resultado motivos perda_evitavel por_que qualidade
              regras teve_pessoa precisava_pessoa origem resumo].freeze
  QUALIDADES = %w[acertou erro_leve erro_grave nao_atuou].freeze
  SEM_INFO = 'sem_info'.freeze
  # O papel -> a lista do catálogo (nil: a lista vem de outro lugar ou o campo não é de lista).
  LISTAS = { 'quem' => 'quem', 'origem' => 'origens', 'tema' => 'temas', 'marcos' => 'marcos', 'resultado' => 'resultados',
             'motivos' => 'motivos', 'regras' => 'regras' }.freeze
  TEXTO = { 'type' => 'string' }.freeze
  # O formato do horário vai descrito no próprio esquema, como a transcrição escreve (o código acha a mensagem).
  HORARIO = { 'type' => 'string', 'description' => 'MM-DD HH:MM em UTC, igual ao horário da linha da transcrição' }.freeze
  SIM_OU_NAO = { 'type' => 'boolean' }.freeze

  def initialize(ficha)
    @catalogo = ficha.catalogo
    @configuracao = ficha.configuracao
    @leitura = @configuracao['leitura'].is_a?(Hash) ? @configuracao['leitura'] : {}
    @com_teste = @leitura['com_teste'] == true
  end

  def json
    propriedades = campos.to_h.transform_keys { |papel| nome(papel) }.merge(extras)
    procura = { 'type' => 'object', 'additionalProperties' => false, 'required' => propriedades.keys, 'properties' => propriedades }
    { 'type' => 'object', 'additionalProperties' => false, 'required' => ['procuras'],
      'properties' => { 'procuras' => { 'type' => 'array', 'items' => procura } } }
  end

  # A resposta já lida do JSON -> [{papel => valor}] na ordem das procuras, com os ids conferidos.
  def procuras(resposta)
    lista = resposta.is_a?(Hash) ? resposta['procuras'] : nil
    raise Invalida, 'sem procuras' unless lista.is_a?(Array) && lista.any?

    lista.map { |item| conferir(item) }
  end

  # O valor de cada corte da ficha numa procura conferida ({id do corte => faixa}).
  def cortes(procura)
    Array(@configuracao['cortes']).to_h do |corte|
      bruto = procura[corte['campo']]
      [corte['id'], corte['faixas'] ? faixa(bruto, corte['faixas']) : bruto]
    end
  end

  private

  def nome(papel) = (@leitura['campos'].is_a?(Hash) && @leitura['campos'][papel]) || papel

  def extras = @leitura['extras'].is_a?(Hash) ? @leitura['extras'] : {}

  # [[papel, esquema]] na ordem da prova: quem é, o pedido, o tema, os cortes, o que aconteceu, a qualidade, a pessoa.
  def campos
    [['conversa', { 'type' => 'integer' }], ['procura', { 'type' => 'integer' }], ['inicio', HORARIO], ['fim', HORARIO],
     *(@com_teste ? [['teste', SIM_OU_NAO]] : []),
     ['quem', um_de(ids('quem'))], ['pedido', um_de(pedidos)], ['tema', um_de(ids('tema'))], *campos_de_corte,
     ['marcos', lista_de(ids('marcos'))], ['resultado', um_de(ids('resultado'))], ['motivos', lista_de(ids('motivos'))],
     ['perda_evitavel', SIM_OU_NAO], ['por_que', TEXTO], ['qualidade', um_de(QUALIDADES)], ['regras', lista_de(ids('regras'))],
     ['teve_pessoa', SIM_OU_NAO], ['precisava_pessoa', SIM_OU_NAO], ['origem', um_de(ids('origem'))], ['resumo', TEXTO]]
  end

  # O corte que é um campo da procura (o pedido) não vira campo novo. Com faixas, a leitura dá o número e o código
  # escolhe a faixa; sem faixas, a leitura escolhe da lista do catálogo.
  def campos_de_corte
    Array(@configuracao['cortes']).filter_map do |corte|
      campo = corte['campo'].to_s
      next if campo.blank? || PAPEIS.include?(campo)

      [campo, corte['faixas'] ? { 'type' => %w[integer null] } : um_de(valores_do_corte(corte))]
    end.uniq(&:first)
  end

  def ids(papel) = (@catalogo[LISTAS.fetch(papel)] || {}).keys

  def valores_do_corte(corte) = (@catalogo.dig('cortes', corte['id']) || {}).keys

  # Os pedidos possíveis: os do corte que lê o pedido; sem ele, os de compra e de dúvida da configuração.
  def pedidos
    corte = Array(@configuracao['cortes']).find { |c| c['campo'] == 'pedido' }
    lista = corte ? valores_do_corte(corte) : []
    lista.presence || (Array(@configuracao['compra_pedidos']) + Array(@configuracao['duvida_pedidos'])).uniq
  end

  def um_de(lista) = { 'type' => 'string', 'enum' => lista }
  def lista_de(lista) = { 'type' => 'array', 'items' => um_de(lista) }

  def conferir(item)
    raise Invalida, 'procura não é objeto' unless item.is_a?(Hash)

    papeis = campos.to_h { |papel, definicao| [papel, conferido(item, papel, definicao)] }
    raise Invalida, 'sem horário' if papeis['inicio'].blank? || papeis['fim'].blank?

    papeis
  end

  def conferido(item, papel, definicao)
    valor = item[nome(papel)]
    permitidos = definicao['enum'] || definicao.dig('items', 'enum')
    return valor if permitidos.nil?

    lista = definicao['type'] == 'array' ? Array(valor) : [valor]
    raise Invalida, "#{papel} fora do catálogo" unless lista.all? { |id| permitidos.include?(id) }

    valor
  end

  # O id da faixa como a carga gravou: '<de>_<até>' ou '<de>_mais' na última.
  def faixa(valor, faixas)
    return SEM_INFO unless valor.is_a?(Integer)

    de, ate = faixas.find { |minimo, maximo, _nome| valor >= minimo && (maximo.nil? || valor <= maximo) }
    return SEM_INFO if de.nil?

    "#{de}_#{ate || 'mais'}"
  end
end
