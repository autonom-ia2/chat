# O que o catálogo da Automação livre (#2414 F5) lê do esquema da receita, para o editor e o Guia: os gatilhos, as
# unidades de tempo e os operadores.
#
# #2499 (F6): o gatilho de card traz o grupo, a flag que pede, a chave de funis (`funil`) e os parâmetros que a pessoa
# escolhe nele (a etapa, o funil), com a frase e se é obrigatório, pelas regras `allOf` do esquema. Os de tempo (PR3)
# trazem também os dias, o campo de data, antes ou depois e a hora.
# G12: o de reunião marca `reunioes` — o editor só oferece com as reuniões da instalação ligadas.
# G50: o que aceita "começa outra vez" quando se repete marca `se_repetir` — só nele o editor pergunta.
module Autonomia::Automacao::CatalogoDoEsquema
  module_function

  def gatilhos(esquema, declarado)
    esquema.dig('properties', 'gatilho', 'properties', 'tipo', 'enum').map do |tipo|
      card = ::Autonomia::Automacao::Gatilhos.do_card?(tipo)
      tempo = ::Autonomia::Automacao::Gatilhos.de_tempo?(tipo)
      { 'tipo' => tipo, 'alvo' => ::Autonomia::Automacao::Gatilhos.alvo(tipo), 'frase' => chave('GATILHOS', tipo),
        'grupo' => grupo(tipo, card, tempo), 'requer' => (::Autonomia::Automacao::Motor::FLAG_GATILHOS if card || tempo),
        'funil' => (true if card), 'reunioes' => (true if ::Autonomia::Automacao::Gatilhos.de_reuniao?(tipo)),
        'se_repetir' => (true if ::Autonomia::Automacao::Gatilhos.pode_repetir?(tipo)),
        'parametros' => parametros(esquema, tipo).presence,
        'filtro_sugerido' => declarado.dig('filtro_sugerido', tipo) }.compact
    end
  end

  # A reunião (G12) é do card, mas fica num grupo próprio no editor: quem procura "reunião" não pensa em "card do funil".
  # #2499 PR3: os de tempo (inclusive o card parado e a data do card) ficam no grupo Tempo.
  def grupo(tipo, card, tempo)
    return 'reuniao' if ::Autonomia::Automacao::Gatilhos.de_reuniao?(tipo)
    return 'tempo' if tempo

    card ? 'card' : 'conversa'
  end

  def parametros(esquema, tipo)
    obrigatorios = Array(esquema.dig('properties', 'gatilho', 'allOf')).flat_map do |regra|
      Array(regra.dig('if', 'properties', 'tipo', 'enum')).include?(tipo) ? Array(regra.dig('then', 'required')) : []
    end
    ::Autonomia::Automacao::Gatilhos.entrada(tipo).parametros.map do |nome|
      { 'nome' => nome, 'peca' => nome.delete_suffix('_id'), 'obrigatorio' => obrigatorios.include?(nome),
        'frase' => chave('PARAMETROS_DO_GATILHO', nome) }
    end
  end

  # As unidades da duração; com `definicao`, as de outra (G69: o `daqui_do_retorno` conta também em meses).
  def unidades(esquema, definicao = 'duracao')
    esquema.dig('definitions', definicao, 'properties', 'unidade', 'enum').map do |unidade|
      { 'valor' => unidade, 'frase' => chave('UNIDADES', unidade) }
    end
  end

  # Cada operador e se ele pede um valor para comparar ("está vazio" não pede).
  def operadores(esquema)
    esquema.dig('definitions', 'condicao', 'oneOf').filter_map do |forma|
      ops = forma.dig('properties', 'op', 'enum')
      ops&.map { |op| { 'op' => op, 'pede_valor' => forma['required'].include?('valor'), 'frase' => chave('OPERADORES', op) } }
    end.flatten
  end

  def chave(*partes) = ::Autonomia::Automacao::Catalogo.chave(*partes)
end
