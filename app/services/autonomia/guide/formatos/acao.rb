# O formato de UMA ação do catálogo (#900): lê o código da action, resolve o
# que só a execução diz (`Resolucao`) e entrega a árvore do corpo para o
# `Corpo` escrever.
class Autonomia::Guide::Formatos::Acao
  Formatos = ::Autonomia::Guide::Formatos

  # O que a action lê e não é corpo: vem do roteador ou do endereço.
  DO_ENDERECO = %w[controller action format account_id].freeze

  def initialize(klass, rota)
    @klass = klass
    @rota = rota
    @motivos = []
  end

  def formato
    @motivos << 'a rota não tem a action no controller: a chamada dá erro' unless @klass.method_defined?(@rota.action)
    @coleta = ler_codigo
    resolucao = Formatos::Resolucao.new(@klass, @coleta, nao_executar: [@rota.action, *callbacks.map(&:to_s)])
    permits = resolucao.permits
    @motivos.concat(resolucao.motivos)
    montar(corpo_para(resolucao), permits)
  end

  private

  def ler_codigo
    leitor = Formatos::Leitor.new(@klass).ler(@rota.action)
    callbacks.each { |callback| leitor.ler(callback, da_action: false) }
    leitor.coleta
  end

  def corpo_para(resolucao)
    modelos = [Formatos::Modelo.resolver(@klass, @coleta), *@coleta.modelos.map(&:modelo)].uniq
    Formatos::Corpo.new(modelos: modelos, criando: @rota.action == 'create', do_endereco: DO_ENDERECO + @rota.partes,
                        por_tipo: resolucao.por_tipo, so_se: resolucao.so_se)
  end

  def montar(corpo, permits)
    permits.each { |caminho, arvore, envelope| corpo.permitir(caminho, arvore, envelope: envelope) }
    @coleta.leituras.each do |leitura|
      next if do_endereco?(leitura.caminho)

      corpo.ler(leitura.caminho, exigida: leitura.exigida, uso: @coleta.tipos[leitura.caminho], repasse: @coleta.repassadas[leitura.caminho])
    end
    @coleta.livres.each { |leitura| corpo.livre(leitura.caminho) }
    corpo.envelope_flexivel(@coleta.envelopes_flexiveis)
    motivos_do_codigo
    corpo.saida(@klass).merge(conclusao(corpo))
  end

  def conclusao(corpo)
    motivos = (@motivos + corpo.motivos).uniq
    {
      'controller' => "#{@rota.controller}##{@rota.action}",
      'completo' => motivos.empty?,
      'motivos' => motivos.presence,
      'sem_corpo' => corpo.vazio? && motivos.empty?,
      'origem' => origem
    }.compact
  end

  def motivos_do_codigo
    @coleta.totais.each { |onde| @motivos << "aceita qualquer campo (permit! em #{onde})" }
    @coleta.repasses.uniq.each { |quem| @motivos << "params inteiro repassado a #{quem}" }
    @motivos << 'lê o corpo cru da requisição' if @coleta.corpo_cru.any?
    @coleta.externos.uniq.each { |quem| @motivos << "termina em código de fora do repositório (super em #{quem})" }
  end

  def do_endereco?(caminho)
    caminho.size == 1 && (DO_ENDERECO.include?(caminho.first) || @rota.partes.include?(caminho.first))
  end

  # Os `before_action` que valem para esta action e moram no controller do
  # recurso. Os da base da API (autenticação, conta) não leem corpo de ação.
  def callbacks
    @callbacks ||= begin
      falso = Struct.new(:action_name, :raise_on_missing_callback_actions).new(@rota.action, false)
      @klass._process_action_callbacks.select { |callback| antes?(callback) && aplica?(callback, falso) }.map(&:filter)
    end
  end

  def antes?(callback)
    callback.kind == :before && callback.filter.is_a?(Symbol) && !infraestrutura?(callback.filter)
  end

  def infraestrutura?(filtro)
    base = Api::V1::Accounts::BaseController
    base.method_defined?(filtro) || base.private_method_defined?(filtro)
  end

  def aplica?(callback, falso)
    se = callback.instance_variable_get(:@if).all? { |condicao| !filtro_de_action?(condicao) || condicao.match?(falso) }
    senao = callback.instance_variable_get(:@unless).any? { |condicao| filtro_de_action?(condicao) && condicao.match?(falso) }
    se && !senao
  end

  # `only:`/`except:` viram `ActionFilter`. Condição em método ou lambda não se
  # avalia sem requisição: conta como aplicável, e o que o callback lê entra.
  def filtro_de_action?(condicao)
    condicao.is_a?(AbstractController::Callbacks::ActionFilter)
  end

  def origem
    definicao = @klass.instance_method(@rota.action).source_location
    inicio = definicao && Formatos::Fontes.do_controller?(definicao.first) ? ["#{Formatos::Fontes.relativo(definicao.first)}:#{definicao.last}"] : []
    (inicio + @coleta.origens).uniq
  rescue NameError
    @coleta.origens
  end
end
