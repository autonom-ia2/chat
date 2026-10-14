# frozen_string_literal: true

# Textos dos pacotes de tradução do servidor (#1550): config/pacotes/<camada>/<idioma>.yml, com raiz no idioma.
# Hash próprio, congelado e lido uma vez por processo (editou o yml, reinicie o servidor). Não instancia outro
# I18n::Backend::Simple: o lookup do pacote não pode chamar o I18n de novo.
module Autonomia::Segmentos::Catalogo
  PASTA = Rails.root.join('config/pacotes')
  MUTEX = Mutex.new
  # Resposta já calculada de cada pedido que pode estar num pacote (o último nome bate com alguma folha). O catálogo é
  # congelado e lido uma vez por processo, então a resposta não muda; a chave do pedido inclui o catálogo em uso. Os
  # pedidos são finitos como as chaves do app; o teto só protege contra chave montada com dado (aí ela é calculada a
  # cada vez, por catálogo, camada e idioma). false guarda "não está no pacote".
  ACHADOS = Concurrent::Map.new
  TETO_DE_ACHADOS = 5_000
  LOG_TAG = '[Autonomia::Segmentos::Catalogo]'

  # A camada mais específica (a última) vence. Só devolve folha String: pedido de subárvore segue no base.
  # Roda em toda tradução de quem está num pacote, antes do base. O caso comum (chave inteira, sem scope) consulta o
  # conjunto das chaves do pacote sem alocar nada e volta na hora quando a chave não está lá; com scope ou separador
  # próprio (raro), filtra pelo último nome e calcula sem guardar.
  def self.procurar(locale, key, scope, separator, camadas)
    if scope.blank? && separator.nil?
      return unless completas.include?(key.is_a?(Symbol) ? key.name : key)

      return procurar_guardado(locale, key, camadas)
    end
    return unless folhas.include?(ultimo_nome(key, separator))

    buscar(planas, camadas, I18n.normalize_keys(locale, key, scope, separator))
  end

  def self.procurar_guardado(locale, key, camadas)
    por_camada = planas
    guardados = gaveta(gaveta(gaveta(ACHADOS, por_camada.object_id), camadas.last), locale)
    achado = guardados[key]
    return achado || nil unless achado.nil?

    valor = buscar(por_camada, camadas, I18n.normalize_keys(locale, key, nil, nil))
    guardados[key.dup.freeze] = valor || false if guardados.size < TETO_DE_ACHADOS
    valor
  end
  private_class_method :procurar_guardado

  # Um nível do guardado (catálogo em uso → camada mais específica → idioma → chave): chaves simples, busca barata.
  def self.gaveta(mapa, chave)
    mapa[chave] || mapa.compute_if_absent(chave) { Concurrent::Map.new }
  end
  private_class_method :gaveta

  def self.buscar(por_camada, camadas, chaves)
    camadas.reverse_each do |camada|
      valor = por_camada[camada]&.[](chaves)
      return valor if valor
    end
    nil
  end
  private_class_method :buscar

  # Um yml ilegível não derruba o I18n de quem está no pacote: o processo fica com o catálogo base até reiniciar, e
  # a falha é lida uma vez só. O check `Fork translations` do CI barra o yml inválido antes do deploy.
  def self.dados
    indice[:dados]
  end

  # Por camada, cada folha de texto pelo caminho inteiro ([:pt_BR, :crm, :export, :statuses, :won] => "Seguro ativo"): um
  # acesso por camada, sem descer a árvore. Só entra a folha que no catálogo base também é texto: chave órfã, plural
  # (one/other) e subárvore do base ficam de fora, e o lookup pode consultar o pacote antes do base sem trocar nada disso.
  def self.planas
    indice[:planas]
  end

  # Caminho de cada folha de todos os pacotes, sem o idioma ("crm.export.statuses.won").
  def self.completas
    indice[:completas]
  end

  # Nomes finais (texto) de todas as folhas de todos os pacotes.
  def self.folhas
    indice[:folhas]
  end

  def self.indice
    @indice || MUTEX.synchronize { @indice ||= montar_indice }
  end
  private_class_method :indice

  def self.montar_indice
    dados = congelar(carregar_ou_vazio)
    planas = planas_contra_o_base(dados)
    caminhos = planas.values.flat_map(&:keys)
    { dados: dados, planas: planas,
      completas: caminhos.to_set { |caminho| caminho.drop(1).map(&:name).join(I18n.default_separator).freeze }.freeze,
      folhas: caminhos.to_set { |caminho| caminho.last.name }.freeze }.freeze
  end
  private_class_method :montar_indice

  # Só fica a folha que no catálogo base também é texto (o resto o CI já barra; aqui é a garantia em tempo de execução).
  def self.planas_contra_o_base(dados)
    base = I18n.backend.translations(do_init: true)
    dados.transform_values do |arvore|
      achatar(arvore).select { |caminho, _| base.dig(*caminho).is_a?(String) }.freeze
    end.freeze
  end
  private_class_method :planas_contra_o_base

  def self.carregar_ou_vazio
    carregar
  rescue StandardError => e
    # Só a classe: a mensagem do parser traz trecho do arquivo.
    Rails.logger.error("#{LOG_TAG} #{e.class} ao ler #{PASTA}; pacotes do servidor no catálogo base até reiniciar")
    {}
  end
  private_class_method :carregar_ou_vazio

  def self.carregar
    Dir.glob(PASTA.join('**', '*.yml').to_s).each_with_object({}) do |arquivo, acc|
      camada = Pathname(arquivo).relative_path_from(PASTA).dirname.to_s
      conteudo = (YAML.safe_load_file(arquivo) || {}).deep_symbolize_keys
      acc[camada] = (acc[camada] || {}).deep_merge(conteudo)
    end
  end
  private_class_method :carregar

  # O catálogo é compartilhado por todas as requisições: congela hashes e textos, não só a raiz.
  def self.congelar(valor)
    case valor
    when Hash then valor.transform_values { |filho| congelar(filho) }.freeze
    when String then valor.dup.freeze
    else valor
    end
  end
  private_class_method :congelar

  def self.achatar(arvore, caminho = [])
    arvore.each_with_object({}) do |(chave, filho), planas|
      if filho.is_a?(Hash)
        planas.merge!(achatar(filho, caminho + [chave]))
      elsif filho.is_a?(String)
        planas[(caminho + [chave]).freeze] = filho
      end
    end
  end
  private_class_method :achatar

  # "crm.export.statuses.won" ou :won (com scope) → "won". Symbol#name não aloca; só a chave com separador aloca o
  # pedaço final.
  def self.ultimo_nome(key, separator)
    texto = key.is_a?(Symbol) ? key.name : key.to_s
    corte = texto.rindex(separator || I18n.default_separator)
    corte ? texto[(corte + 1)..] : texto
  end
  private_class_method :ultimo_nome
end
