# O que a amostra e o lote fazem igual com cada item de uma tarefa longa (#936), ANTES de escrever:
# lê o registro de agora, pergunta ao Jev (quando a receita classifica), pede os valores do `$gerar`
# e monta o caminho e o corpo da ação. Nada é gravado aqui.
#
# O item que não vai ser mudado sai com o motivo (`pulado`), para o relatório agrupar.
class Autonomia::Guide::Tarefas::Preparo
  Preparado = Struct.new(:id, :registro, :escolha, :certeza, :dados, :motivo, keyword_init: true)
  CotaEsgotada = Class.new(StandardError)
  Montador = ::Autonomia::Guide::Tarefas::Montador
  ROTULOS = %w[name title label subject].freeze

  attr_reader :classificados

  def initialize(contexto:, receita:)
    @contexto = contexto
    @receita = receita
    @alvos = ::Autonomia::Guide::Tarefas::Alvos.new(consulta: contexto.consulta, receita: receita)
    @jev = ::Autonomia::Guide::Tarefas::Jev.new(account: contexto.account, receita: receita) if receita.usa_jev?
    @gerador = ::Autonomia::Guide::Tarefas::Gerador.new(account: contexto.account)
    @classificados = 0
  end

  def self.rotulo(registro, id)
    ROTULOS.filter_map { |campo| registro.to_h[campo].presence }.first.to_s.presence || "##{id}"
  end

  # `prazo`: hora (monotônica) em que para de ler itens novos; os que ficam de fora não voltam na lista.
  # Levanta CotaEsgotada quando acaba a cota do Jev, e Gerador::Falhou quando a IA do cliente falha.
  def preparar(ids, prazo: nil)
    lidos = []
    ids.each do |id|
      break if prazo && relogio >= prazo

      lidos << ler_e_classificar(id)
    end
    montar(lidos)
  end

  def custo
    @gerador.custo
  end

  private

  def ler_e_classificar(id)
    registro = @alvos.ler(id)
    return Preparado.new(id: id, motivo: 'nao_encontrado') if registro.nil?
    return Preparado.new(id: id, registro: registro) unless @jev

    classificar(Preparado.new(id: id, registro: registro))
  end

  def classificar(preparado)
    raise CotaEsgotada if ::Autonomia::Guide::Tarefas::Jev.restante(@contexto.account) <= 0

    resultado = @jev.classificar(preparado.registro)
    @classificados += 1
    preparado.escolha = resultado.resposta
    preparado.certeza = resultado.certeza
    preparado.motivo = motivo_da_classificacao(resultado) unless @jev.agir?(resultado)
    preparado
  rescue TypesafeAi::Decisor::Error
    preparado.motivo = 'jev_falhou'
    preparado
  end

  def motivo_da_classificacao(resultado)
    @receita.agir_quando.include?(resultado.resposta.to_s) ? 'certeza_baixa' : 'fora_da_classificacao'
  end

  def montar(lidos)
    a_mudar = lidos.reject(&:motivo)
    gerados = @receita.gerar.empty? || a_mudar.empty? ? {} : @gerador.gerar(pedidos(a_mudar))
    a_mudar.each { |preparado| montar_um(preparado, gerados[preparado.id.to_s] || {}) }
    lidos
  end

  def pedidos(a_mudar)
    @receita.gerar.index_with do |argumento|
      a_mudar.to_h { |preparado| [preparado.id.to_s, Montador.campo(preparado.registro, argumento['campo'])] }
    end
  end

  def montar_um(preparado, gerados)
    montador = Montador.new(registro: preparado.registro, escolha: preparado.escolha, gerados: gerados)
    preparado.dados = { caminho: montador.montar(@receita.caminho), corpo: montador.montar(@receita.corpo),
                        descricao: @receita.descricao }
  rescue KeyError
    preparado.motivo = 'sem_valor_gerado'
  end

  def relogio
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
