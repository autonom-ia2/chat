# O corpo que uma ação aceita, montado a partir do que o código leu (#900), e
# escrito no formato do JSON: envelope, se o corpo plano também serve, e cada
# campo com o que o modelo diz dele.
#
# O envelope importa por causa do `wrap_parameters`: ele só embrulha sozinho as
# chaves que são coluna do modelo. Campo que não é coluna, mandado solto numa
# action que faz `require(:x)`, some — por isso `so_no_envelope` lista esses.
class Autonomia::Guide::Formatos::Corpo
  Formatos = ::Autonomia::Guide::Formatos
  Filtros = Formatos::Filtros
  SEM_MODELO = { lista: 'lista', livre: 'objeto_livre', aninhado: 'objeto' }.freeze

  attr_reader :motivos

  # `do_endereco`: nomes que vêm do roteador ou do endereço (`id`,
  # `account_id`, `inbox_id` de rota aninhada) — o `permit(:id)` não os torna corpo.
  # `modelos`: o do recurso primeiro (pode ser nil) e depois os outros que a
  # action usa. Leitura crua que não é coluna do recurso (`custom_role_id` na
  # criação de agente) pega o tipo da coluna de mesmo nome num deles.
  def initialize(modelos:, criando:, do_endereco: [], por_tipo: {}, so_se: {})
    @modelo, *vizinhos = modelos
    @vizinhos = vizinhos.compact
    @do_endereco = do_endereco
    @criando = criando
    @por_tipo = por_tipo
    @so_se = so_se
    @raiz = {}
    @envelopes = []
    @motivos = []
    @sem_tipo = []
  end

  def permitir(caminho, arvore, envelope:)
    @envelopes << caminho.first if envelope && caminho.size == 1
    arvore = arvore.except(*@do_endereco) if caminho.empty?
    @permit_na_raiz = true if caminho.empty? && arvore.any?
    @raiz = colocar(@raiz, caminho, arvore)
  end

  def ler(caminho, exigida:)
    @raiz = colocar(@raiz, caminho[0...-1], { caminho.last => { forma: :escalar, cru: true, exigida: exigida } })
  end

  def livre(caminho)
    @raiz = colocar(@raiz, caminho[0...-1], { caminho.last => { forma: :livre } })
  end

  def envelope_flexivel(chaves)
    @flexiveis = chaves.uniq
    @envelopes.concat(@flexiveis)
  end

  def vazio?
    @raiz.empty?
  end

  def saida(klass)
    envelope = escolher_envelope
    campos = envelope ? @raiz[envelope][:campos] : @raiz
    saida = { 'modelo' => @modelo&.name, 'envelope' => envelope }.merge(plano(klass, envelope, campos))
    saida['campos'] = campos_json(campos, @modelo, raiz: true).presence
    saida['fora_do_envelope'] = campos_json(@raiz.except(envelope), @modelo) if envelope && @raiz.size > 1
    @motivos << "leitura crua sem tipo: #{@sem_tipo.uniq.sort.join(', ')}" if @sem_tipo.any?
    saida.compact
  end

  private

  def colocar(nivel, caminho, arvore)
    return Filtros.juntar(nivel, arvore) if caminho.empty?

    chave, *resto = caminho
    atual = nivel[chave] || { forma: :aninhado, campos: {}, cru: true }
    atual = atual.merge(forma: :aninhado, campos: {}) if atual[:forma] == :escalar
    return nivel unless atual[:forma] == :aninhado

    nivel.merge(chave => atual.merge(campos: colocar(atual[:campos] || {}, resto, arvore)))
  end

  # Só há envelope quando nenhum `permit` lê da raiz: o `require(:channel)` da
  # caixa de voz é um campo `channel`, não o envelope da criação de caixa.
  def escolher_envelope
    return if @permit_na_raiz

    candidatos = @envelopes.uniq.select { |chave| @raiz.dig(chave, :forma) == :aninhado }
    candidatos.first if candidatos.size == 1
  end

  def plano(klass, envelope, campos)
    return {} unless envelope
    return { 'corpo_plano' => true } if Array(@flexiveis).include?(envelope)

    opcoes = klass._wrapper_options
    return { 'corpo_plano' => false } unless opcoes.format.include?(:json) && opcoes.name == envelope

    fora = opcoes.include ? campos.keys.grep_v(Filtros::Dinamico) - opcoes.include.map(&:to_s) : []
    { 'corpo_plano' => fora.empty?, 'so_no_envelope' => fora.sort.presence }.compact
  end

  def campos_json(arvore, modelo, raiz: false, prefixo: nil)
    arvore.reject { |nome, _| nome.is_a?(Filtros::Dinamico) }.sort.to_h do |nome, campo|
      [nome, campo_json(nome, campo, modelo, raiz, [prefixo, nome].compact.join('.'))]
    end
  end

  def campo_json(nome, campo, modelo, raiz, caminho)
    json = Formatos::Modelo.anotar(modelo, nome, campo, criando: @criando)
    json['tipo'] ||= tipo_sem_modelo(nome, campo)
    json['obrigatorio'] = true if campo[:exigida]
    json['so_se'] = @so_se[caminho]
    json.merge!(dentro(nome, campo, modelo, raiz, caminho))
    @sem_tipo << caminho if campo[:cru] && campo[:forma] == :escalar && json['tipo'].nil?
    json.compact.sort.to_h
  end

  def tipo_sem_modelo(nome, campo)
    return SEM_MODELO[campo[:forma]] if SEM_MODELO.key?(campo[:forma])

    tipo_vizinho(nome) if campo[:cru]
  end

  def dentro(nome, campo, modelo, raiz, caminho)
    extra = {}
    extra['campos'] = campos_json(campo[:campos] || {}, submodelo(modelo, nome), prefixo: caminho) if campo[:forma] == :aninhado
    extra.merge!(canal) if raiz && nome == Formatos::Canais::CAMPO && @por_tipo.any?
    extra
  end

  def tipo_vizinho(nome)
    @vizinhos.lazy.filter_map { |vizinho| Formatos::Modelo.tipo_escalar(vizinho, nome, vizinho.columns_hash[nome]) }.first
  end

  def canal
    por_tipo = @por_tipo.sort_by { |classe, _| classe.name }.to_h do |classe, arvore|
      [classe.name, campos_json(arvore, classe)]
    end
    { 'depende_de' => Formatos::Canais::DEPENDE_DE, 'por_tipo' => por_tipo }
  end

  def submodelo(modelo, nome)
    associacao = modelo&.reflect_on_association(nome)
    associacao.klass if associacao && !associacao.polymorphic?
  rescue NameError
    nil
  end
end
