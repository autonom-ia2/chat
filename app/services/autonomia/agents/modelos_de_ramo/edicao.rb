# O DONO MUDA O MODELO PRONTO ANTES DE COMEÇAR (#2881, pedido do Rodrigo): tirar, editar e incluir perguntas e
# documentos; tirar ferramenta, incluir as do "Também combina" e alterar a frase "Use quando" de cada uma. Tudo fica no
# `state` da conversa (sem migration) e, quando o rascunho do agente já existe, também na marca dele (`config`), que é
# de onde o agente que atende lê as listas. Nenhuma chamada de IA.
#
# Cada lista que vem substitui a lista inteira; a que não vem fica como está.
#   perguntas / documentos: [{ id, texto, tirada }] — `id` de um item que já existe o mantém; sem `id` (ou com um que
#     a lista não tem) é item novo e ganha id aqui. `tirada: true` deixa o item guardado, fora do agente.
#   ferramentas: [{ fonte, usar_quando }] — o "Já vem com" inteiro. `fonte` só as do modelo; sem `usar_quando` (ou
#     vazio), a frase do ramo.
#
# Validação estrita, e nada é gravado quando algo falha (`Recusada#motivo` e `#campo`): só texto, até 20 itens por
# lista, até 300 letras por item, a frase no limite do "Incluir". Recusa também a conversa sem modelo (conta sem o
# pacote `seguros`, flag desligada, a Lia: `sem_modelo`) e o agente que já começou a atender (`agente_ja_comecou`).
class Autonomia::Agents::ModelosDeRamo::Edicao
  LISTAS = %w[perguntas documentos].freeze
  FERRAMENTAS = 'ferramentas'.freeze
  VALORES_DE_TIRADA = [true, false, 'true', 'false', nil].freeze

  class Recusada < StandardError
    attr_reader :campo

    def initialize(motivo, campo = nil)
      super(motivo)
      @campo = campo
    end

    def motivo
      message
    end
  end

  def initialize(thread:, mudancas:)
    @thread = thread
    @mudancas = mudancas.to_h.deep_stringify_keys
  end

  # -> o Rascunho com as mudanças, já gravadas. Lê e grava com a conversa travada (a trava relê a conversa): duas edições
  # ao mesmo tempo (duas abas, ou um pedido só de perguntas e outro só de documentos) entram uma depois da outra, e a
  # segunda parte do que a primeira gravou. Sem a trava, cada uma regravaria a marca inteira e apagaria a outra.
  def call
    @thread.with_lock do
      rascunho = Autonomia::Agents::ModelosDeRamo::Rascunho.do_thread(@thread)
      recusar('sem_modelo') if rascunho.nil?

      novo = rascunho.com(rascunho.marca.merge(listas(rascunho.marca), ferramentas(rascunho.modelo)))
      gravar!(novo)
      novo
    end
  end

  private

  def recusar(motivo, campo = nil)
    raise Recusada.new(motivo, campo)
  end

  def lista_valida?(valor)
    valor.is_a?(Array) && valor.size <= Autonomia::Agents::ModelosDeRamo::ITENS_MAX && valor.all?(Hash)
  end

  def listas(marca)
    LISTAS.select { |campo| @mudancas.key?(campo) }.index_with do |campo|
      recusar('lista_invalida', campo) unless lista_valida?(@mudancas[campo])

      atuais = Autonomia::Agents::ModelosDeRamo::Marca.itens(marca, campo).pluck('id')
      @mudancas[campo].reduce([]) { |prontos, bruto| prontos + [item(campo, bruto, atuais, prontos.pluck('id'))] }
    end
  end

  def item(campo, bruto, atuais, usados)
    texto = bruto['texto'].is_a?(String) ? bruto['texto'].squish : ''
    recusar('texto_invalido', campo) if texto.empty? || texto.length > Autonomia::Agents::ModelosDeRamo::ITEM_MAX
    recusar('tirada_invalida', campo) unless VALORES_DE_TIRADA.include?(bruto['tirada'])

    { 'id' => id_do_item(campo, bruto['id'], atuais, usados), 'texto' => texto,
      'tirada' => ActiveModel::Type::Boolean.new.cast(bruto['tirada']) == true }
  end

  # O id que veio só vale se é de um item que a lista já tem; dois itens com o mesmo id são recusados.
  def id_do_item(campo, id, atuais, usados)
    return Autonomia::Agents::ModelosDeRamo::Marca.proximo_id(campo, atuais + usados) unless atuais.include?(id)

    recusar('id_repetido', campo) if usados.include?(id)
    id
  end

  def ferramentas(modelo)
    return {} unless @mudancas.key?(FERRAMENTAS)

    brutas = @mudancas[FERRAMENTAS]
    recusar('lista_invalida', FERRAMENTAS) unless lista_valida?(brutas)

    frases = modelo.ferramentas.to_h { |ferramenta| [ferramenta.fonte, ferramenta.usar_quando] }
    recusar('fonte_invalida', FERRAMENTAS) unless fontes_do_modelo?(brutas.pluck('fonte'), frases)

    { FERRAMENTAS => brutas.map { |bruta| { 'fonte' => bruta['fonte'], 'usar_quando' => frase(bruta['usar_quando'], frases[bruta['fonte']]) } } }
  end

  # Só fonte do próprio modelo ("Já vem com" e "Também combina"), cada uma uma vez.
  def fontes_do_modelo?(fontes, frases)
    fontes.all? { |fonte| frases.key?(fonte) } && fontes.uniq.size == fontes.size
  end

  def frase(usar_quando, do_ramo)
    return do_ramo if usar_quando.nil?

    limpa = usar_quando.is_a?(String) ? usar_quando.squish : nil
    recusar('usar_quando_invalido', FERRAMENTAS) if limpa.nil? || limpa.length > Autonomia::FerramentasProntas::Incluir::MAX_USAR_QUANDO
    limpa.presence || do_ramo
  end

  # Com a conversa já travada: primeiro o agente, se já existir, travado e conferido de novo como rascunho (o "Começar"
  # pode chegar no meio da edição, e a lista não pode entrar num agente que já atende); depois a conversa. A ordem das
  # travas é a do Construtor: conversa, depois agente. A recusa desfaz tudo.
  def gravar!(rascunho)
    chaves = rascunho.para_guardar
    agente = @thread.agent
    agente&.with_lock do
      recusar('agente_ja_comecou') unless agente.draft?
      agente.update!(config: agente.config.to_h.merge(chaves))
    end
    @thread.juntar_ao_estado!(chaves)
  end
end
