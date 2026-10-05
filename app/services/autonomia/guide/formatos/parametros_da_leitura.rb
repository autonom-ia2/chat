# Os parâmetros que UMA leitura do catálogo (`GET conversations`) de fato lê, tirados do código (#942).
#
# Mesma classe de problema que a escrita teve (#900): parâmetro que a rota não lê é ignorado calado.
# O Guia criou uma vigia de conversas com `unassigned_for_more_than_seconds`, a plataforma ignorou, e a
# vigia passou a contar todas as conversas sem responsável. Aqui o `Leitor` da escrita lê a action e os
# `before_action` dela; quando o controller entrega o `params` inteiro a uma classe nossa
# (`ConversationFinder.new(Current.user, params)`), segue até ela (`Repassado`).
#
# Quando o código não deixa saber com certeza, a leitura fica SEM lista (`motivos`), e o Guia não
# recusa nada nela: recusar por um palpite quebraria leitura que funciona.
class Autonomia::Guide::Formatos::ParametrosDaLeitura
  Formatos = ::Autonomia::Guide::Formatos

  def initialize(klass, rota)
    @klass = klass
    @rota = rota
    @motivos = []
  end

  def formato
    return sem_lista(['a rota não tem a action no controller']) unless @klass.method_defined?(@rota.action)

    @coleta = ler_codigo
    nomes = (do_controller + repassados).uniq - Formatos::Acao::DO_ENDERECO - @rota.partes
    motivos_do_codigo
    return sem_lista(@motivos.uniq) if @motivos.any?

    { 'controller' => controller, 'parametros' => nomes.sort }
  end

  private

  def ler_codigo
    leitor = Formatos::Leitor.new(@klass).ler(@rota.action)
    Formatos::Acao.new(@klass, @rota).callbacks.each { |callback| leitor.ler(callback, da_action: false) }
    leitor.coleta
  end

  # O primeiro nível de cada `params[:x]` e de cada `permit`.
  def do_controller
    lidas = @coleta.leituras.map { |leitura| leitura.caminho.first }
    permitidas = @coleta.permits.flat_map do |permit|
      next [permit.caminho.first] if permit.caminho.any?

      arvore = Formatos::Filtros.arvore(permit.filtros)
      @motivos << 'permit com valor calculado' if Formatos::Filtros.dinamica?(arvore)
      arvore.keys.grep(String)
    end
    livres = @coleta.livres.map { |leitura| leitura.caminho.first }
    lidas + permitidas + livres
  end

  # O que a classe que recebeu o `params` inteiro lê. Repasse que não se segue fica nos motivos.
  def repassados
    @coleta.repasses.uniq.flat_map do |quem|
      chaves = seguir(quem)
      next chaves if chaves

      @motivos << "params inteiro repassado a #{quem}"
      []
    end
  end

  def seguir(quem)
    destino = @coleta.para_classe.find { |para| para.quem == quem }
    return unless destino

    classe = destino.modulo.const_get(destino.constante.delete_prefix('::'))
    Formatos::Repassado.chaves(classe, destino.posicao) if classe.is_a?(Class)
  rescue NameError
    nil
  end

  def motivos_do_codigo
    @coleta.totais.each { |onde| @motivos << "aceita qualquer parâmetro (permit! em #{onde})" }
    @motivos << 'lê o corpo cru da requisição' if @coleta.corpo_cru.any?
    @coleta.externos.uniq.each { |quem| @motivos << "termina em código de fora do repositório (super em #{quem})" }
    @coleta.de_fora.uniq.each { |quem| @motivos << "lê params em código de fora do repositório (#{quem})" }
  end

  def sem_lista(motivos)
    { 'controller' => controller, 'motivos' => motivos }
  end

  def controller
    "#{@rota.controller}##{@rota.action}"
  end
end
