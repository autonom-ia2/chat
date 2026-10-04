# A receita de uma tarefa longa (#936), conferida na forma antes de virar amostra.
#
#   { "descricao": "Arrumar o nome dos contatos",
#     "alvo": { "recurso": "contacts", "parametros": {}, "filtro": [{ "campo": "…", "op": "menor", "valor": … }] },
#     "acao": "PATCH contacts/:id",
#     "caminho": { "id": { "$item": "id" } },
#     "corpo": { "name": { "$gerar": { "campo": "name", "instrucao": "…" } } },
#     "classificar": { "pergunta": "…", "opcoes": [{ "chave": "sim", "descricao": "…" }],
#                      "agir_quando": ["sim"], "certeza_minima": 0.8 } }
#
# Uma ação por item (mais de uma está fora do escopo). Os problemas voltam em frases curtas para o
# modelo corrigir e chamar de novo.
class Autonomia::Guide::Tarefas::Receita
  Montador = ::Autonomia::Guide::Tarefas::Montador
  OPERADORES = %w[igual diferente menor maior vazio preenchido].freeze
  OPCOES = (2..8)
  CERTEZA_PADRAO = 0.7
  MAX_DESCRICAO = 200

  attr_reader :dados

  def initialize(dados)
    @dados = dados.is_a?(Hash) ? dados.deep_stringify_keys : {}
  end

  def descricao = @dados['descricao'].to_s.strip
  def acao = @dados['acao'].to_s.strip
  def alvo = @dados['alvo'].is_a?(Hash) ? @dados['alvo'] : {}
  def recurso = alvo['recurso'].to_s.strip.delete_prefix('/')
  def parametros = alvo['parametros'].is_a?(Hash) ? alvo['parametros'] : {}
  def filtro = Array(alvo['filtro'])
  def caminho = @dados['caminho'].is_a?(Hash) ? @dados['caminho'] : {}
  def corpo = @dados['corpo'].is_a?(Hash) ? @dados['corpo'] : {}
  def classificar = @dados['classificar'].is_a?(Hash) ? @dados['classificar'] : nil

  def certeza_minima
    (classificar || {}).fetch('certeza_minima', CERTEZA_PADRAO).to_f
  end

  def agir_quando
    Array(classificar&.dig('agir_quando')).map(&:to_s)
  end

  # Os pedidos de `$gerar` da receita, sem repetir.
  def gerar
    marcas.filter_map { |marca, argumento| argumento if marca == Montador::GERAR }.uniq
  end

  def usa_jev?
    classificar.present?
  end

  def problemas
    @problemas ||= [*do_basico, *do_filtro, *do_classificar, *das_marcas].compact
  end

  private

  def marcas
    Montador.marcas(caminho) + Montador.marcas(corpo)
  end

  def do_basico
    [("falta 'descricao' (uma frase do que vai mudar, até #{MAX_DESCRICAO} letras)" unless descricao.length.between?(1, MAX_DESCRICAO)),
     ("falta 'alvo.recurso' (a leitura que lista os registros, como em ler_da_conta)" if recurso.blank?),
     ("falta 'acao' (uma só, em linguagem de rota)" if acao.blank?),
     ("'corpo' e 'caminho' têm de ser objetos" if invalido?('corpo') || invalido?('caminho'))]
  end

  def invalido?(chave)
    @dados.key?(chave) && !@dados[chave].is_a?(Hash)
  end

  def do_filtro
    filtro.each_with_index.filter_map do |condicao, indice|
      next if condicao.is_a?(Hash) && condicao['campo'].present? && OPERADORES.include?(condicao['op'].to_s)

      "filtro #{indice + 1}: precisa de 'campo' e de 'op' (#{OPERADORES.join(', ')})"
    end
  end

  def do_classificar
    return [] unless classificar

    chaves = chaves_das_opcoes
    [("classificar: falta 'pergunta'" if classificar['pergunta'].to_s.strip.empty?),
     ("classificar: mande de #{OPCOES.min} a #{OPCOES.max} opções com 'chave' única e 'descricao'" unless opcoes_validas?(chaves)),
     ("classificar: 'agir_quando' tem de listar chaves das opções" unless agir_quando_valido?(chaves)),
     ("classificar: 'certeza_minima' vai de 0 a 1" unless certeza_minima.between?(0, 1))]
  end

  def chaves_das_opcoes
    Array(classificar['opcoes']).map { |opcao| opcao.is_a?(Hash) ? opcao['chave'].to_s : '' }
  end

  def agir_quando_valido?(chaves)
    agir_quando.any? && (agir_quando - chaves).empty?
  end

  def opcoes_validas?(chaves)
    opcoes = Array(classificar['opcoes'])
    OPCOES.cover?(chaves.size) && chaves.all?(&:present?) && chaves.uniq.size == chaves.size &&
      opcoes.all? { |opcao| opcao['descricao'].to_s.strip.present? }
  end

  def das_marcas
    marcas.filter_map do |marca, argumento|
      case marca
      when Montador::ITEM then "'$item' leva o nome de um campo do registro" if argumento.to_s.strip.empty?
      when Montador::JEV then "'$jev' precisa de 'classificar' na receita" unless usa_jev?
      when Montador::GERAR then do_gerar(argumento)
      end
    end
  end

  def do_gerar(argumento)
    return if argumento.is_a?(Hash) && argumento['campo'].to_s.strip.present? && argumento['instrucao'].to_s.strip.present?

    "'$gerar' leva {campo, instrucao}: o campo do registro e o que fazer com ele"
  end
end
