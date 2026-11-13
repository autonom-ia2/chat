# O DONO MUDA O MODELO PRONTO (#2881, pedido do Rodrigo): tirar, editar e incluir perguntas e documentos; tirar
# ferramenta, incluir as do "Também combina" e alterar a frase "Use quando" de cada uma. Tudo fica no `state` da
# conversa (sem migration) e, quando o rascunho do agente já existe, também na marca dele (`config`), que é de onde o
# agente que atende lê as listas. Pelo agente sem conversa (a tela reaberta, ou a página dele), só na marca dele.
# Nenhuma chamada de IA.
#
# DEPOIS DO "COMEÇAR" (#2976): perguntas e documentos continuam mudando, pelo agente (`agent:`, a página dele). A
# mudança vale no turno seguinte, porque o agente lê as listas da marca a cada turno (`Instrucao`). As ferramentas não
# mudam mais por aqui: no agente que atende elas são as da gaveta "Ferramentas", e a marca já não decide nada. Pela
# conversa de criação também não: ela ficou para trás.
#
# Cada lista que vem substitui a lista inteira; a que não vem fica como está.
#   perguntas / documentos: [{ id, texto, tirada }] — `id` de um item que já existe o mantém; sem `id` (ou com um que
#     a lista não tem) é item novo e ganha id aqui. `tirada: true` deixa o item guardado, fora do agente.
#   ferramentas: [{ fonte, usar_quando }] — o "Já vem com" inteiro. `fonte` só as do modelo; sem `usar_quando` (ou
#     vazio), a frase do ramo.
#
# Validação estrita, e nada é gravado quando algo falha (`Recusada#motivo` e `#campo`): só texto, até 20 itens por
# lista, até 300 letras por item, a frase no limite do "Incluir". Recusa também a conversa sem modelo (conta sem o
# pacote `seguros`, flag desligada, a Lia: `sem_modelo`) e, no agente que já começou a atender, o que não muda mais
# (`agente_ja_comecou`: tudo pela conversa; as ferramentas pelo agente).
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

  # `thread:` — pela conversa do Construtor (a criação em andamento). `agent:` — pelo agente, sem a conversa: o rascunho
  # que a tela reabriu, ou o agente que já atende (a página dele). Um dos dois.
  def initialize(mudancas:, thread: nil, agent: nil)
    @thread = thread
    @agent = agent
    @mudancas = mudancas.to_h.deep_stringify_keys
  end

  # -> o Rascunho com as mudanças, já gravadas. Lê e grava com tudo travado, na ordem do Construtor (conversa, depois
  # agente; cada trava relê o registro): duas edições ao mesmo tempo (duas abas, um pedido só de perguntas e outro só de
  # documentos, um pela conversa e outro pelo agente) entram uma depois da outra, e a segunda parte do que a primeira
  # gravou. Sem as travas, cada uma regravaria a marca inteira e apagaria a outra.
  def call
    return com_o_agente_travado(@agent) if @thread.nil?

    @thread.with_lock { com_o_agente_travado(@thread.agent) }
  end

  private

  def negar(motivo, campo = nil)
    raise Recusada.new(motivo, campo)
  end

  # A conversa ainda sem rascunho não tem agente para travar.
  def com_o_agente_travado(agente)
    return editar(agente) if agente.nil?

    agente.with_lock { editar(agente) }
  end

  # O "Começar" pode chegar no meio da edição: por isso o rascunho é conferido aqui, com o agente travado, e o que
  # não muda mais depois dele é recusado pelo estado que o agente tem agora. A recusa desfaz tudo.
  def editar(agente)
    rascunho = rascunho_de(agente)
    negar('sem_modelo') if rascunho.nil?
    ja_atende = agente.present? && !agente.draft?
    recusar_o_que_nao_muda_mais if ja_atende

    novo = rascunho.com(rascunho.marca.merge(listas(rascunho.marca), ferramentas(rascunho)))
    chaves = ja_atende ? novo.para_guardar.slice(Autonomia::Agents::ModelosDeRamo::Marca::CHAVE) : novo.para_guardar
    gravar_no_agente(agente, chaves) if agente
    @thread&.juntar_ao_estado!(chaves)
    novo
  end

  def rascunho_de(agente)
    return Autonomia::Agents::ModelosDeRamo::Rascunho.do_thread(@thread) if @thread

    Autonomia::Agents::ModelosDeRamo::Rascunho.do_agente(agente)
  end

  # No agente que já atende: pela conversa de criação nada muda, e as ferramentas não mudam por aqui. Só a marca é
  # gravada nele (`editar`): as chaves das prontas são da criação, e regravá-las mexeria no cartão "pode ganhar".
  def recusar_o_que_nao_muda_mais
    negar('agente_ja_comecou') if @thread
    negar('agente_ja_comecou', FERRAMENTAS) if @mudancas.key?(FERRAMENTAS)
  end

  # Só a coluna `config`, sem tocar no `updated_at` (como a sugestão de prontas, `SugestaoParaAgente.gravar`): o
  # Desfazer e a correção de um ajuste em andamento conferem o `updated_at` do agente, e mudar uma lista não é mudar o
  # agente para eles. O agente está travado e recém-relido; as chaves foram conferidas acima.
  def gravar_no_agente(agente, chaves)
    agente.update_columns(config: agente.config.to_h.merge(chaves)) # rubocop:disable Rails/SkipsModelValidations
  end

  def lista_valida?(valor)
    valor.is_a?(Array) && valor.size <= Autonomia::Agents::ModelosDeRamo::ITENS_MAX && valor.all?(Hash)
  end

  def listas(marca)
    LISTAS.select { |campo| @mudancas.key?(campo) }.index_with do |campo|
      negar('lista_invalida', campo) unless lista_valida?(@mudancas[campo])

      atuais = Autonomia::Agents::ModelosDeRamo::Marca.itens(marca, campo).pluck('id')
      @mudancas[campo].reduce([]) { |prontos, bruto| prontos + [item(campo, bruto, atuais, prontos.pluck('id'))] }
    end
  end

  def item(campo, bruto, atuais, usados)
    texto = bruto['texto'].is_a?(String) ? bruto['texto'].squish : ''
    negar('texto_invalido', campo) if texto.empty? || texto.length > Autonomia::Agents::ModelosDeRamo::ITEM_MAX
    negar('tirada_invalida', campo) unless VALORES_DE_TIRADA.include?(bruto['tirada'])

    { 'id' => id_do_item(campo, bruto['id'], atuais, usados), 'texto' => texto,
      'tirada' => ActiveModel::Type::Boolean.new.cast(bruto['tirada']) == true }
  end

  # O id que veio só vale se é de um item que a lista já tem; dois itens com o mesmo id são recusados.
  def id_do_item(campo, id, atuais, usados)
    return Autonomia::Agents::ModelosDeRamo::Marca.proximo_id(campo, atuais + usados) unless atuais.include?(id)

    negar('id_repetido', campo) if usados.include?(id)
    id
  end

  def ferramentas(rascunho)
    return {} unless @mudancas.key?(FERRAMENTAS)

    brutas = @mudancas[FERRAMENTAS]
    negar('lista_invalida', FERRAMENTAS) unless lista_valida?(brutas)

    frases = rascunho.modelo.ferramentas.to_h { |ferramenta| [ferramenta.fonte, ferramenta.usar_quando] }
    negar('fonte_invalida', FERRAMENTAS) unless fontes_do_modelo?(brutas.pluck('fonte'), frases)

    novas = brutas.map { |bruta| { 'fonte' => bruta['fonte'], 'usar_quando' => frase(bruta['usar_quando'], frases[bruta['fonte']]) } }
    { FERRAMENTAS => novas + fora_da_tela(rascunho, novas.pluck('fonte')) }
  end

  # As ferramentas da marca que a tela não recebe (a fase da fonte está desligada na conta, ou a pessoa a dispensou
  # neste agente): a lista que chega nunca as traz, e não é por isso que elas saem do modelo. Ficam como estavam.
  def fora_da_tela(rascunho, enviadas)
    na_tela = (rascunho.ferramentas + rascunho.tambem).pluck('fonte') + enviadas
    Autonomia::Agents::ModelosDeRamo::Marca.ferramentas(rascunho.marca).reject { |ferramenta| na_tela.include?(ferramenta['fonte']) }
  end

  # Só fonte do próprio modelo ("Já vem com" e "Também combina"), cada uma uma vez.
  def fontes_do_modelo?(fontes, frases)
    fontes.all? { |fonte| frases.key?(fonte) } && fontes.uniq.size == fontes.size
  end

  def frase(usar_quando, do_ramo)
    return do_ramo if usar_quando.nil?

    limpa = usar_quando.is_a?(String) ? usar_quando.squish : nil
    negar('usar_quando_invalido', FERRAMENTAS) if limpa.nil? || limpa.length > Autonomia::FerramentasProntas::Incluir::MAX_USAR_QUANDO
    limpa.presence || do_ramo
  end
end
