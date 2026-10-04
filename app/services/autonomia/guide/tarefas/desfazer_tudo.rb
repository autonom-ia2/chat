# "Desfazer tudo" de uma tarefa longa (#936): o desfazer de cada lote, do último para o primeiro, num
# job. Cada lote volta pela mesma `Desfazer` do turno do Guia (#855) — o conflito preserva a edição
# humana e vira linha do relatório. O progresso fica na tarefa, lote a lote, para a tela mostrar.
class Autonomia::Guide::Tarefas::DesfazerTudo
  MAX_CONFLITOS = 50

  def initialize(tarefa)
    @tarefa = tarefa
    @relatorio = { 'desfeitas' => 0, 'conflitos' => [], 'conflitos_total' => 0, 'lotes' => 0, 'lotes_desfeitos' => 0 }
  end

  def perform
    execucoes = @tarefa.execucoes.where(desfeita_em: nil).order(id: :desc).to_a
    @relatorio['lotes'] = execucoes.size
    execucoes.each { |execucao| desfazer(execucao) }
    @tarefa.update!(status: ::Autonomia::Guide::Tarefa::DESFEITA, relatorio: @tarefa.relatorio.merge('desfazer' => @relatorio))
  end

  private

  def desfazer(execucao)
    resultado = ::Autonomia::Guide::Desfazer.new(execucao: execucao, user: @tarefa.user).perform
    somar(resultado)
  rescue ::Autonomia::Guide::Desfazer::Recusado => e
    @relatorio['recusados'] = Array(@relatorio['recusados']) + [e.message]
  ensure
    @relatorio['lotes_desfeitos'] += 1
    @tarefa.update!(relatorio: @tarefa.relatorio.merge('desfazer' => @relatorio))
  end

  def somar(resultado)
    @relatorio['desfeitas'] += resultado['desfeitas'].to_i
    conflitos = Array(resultado['conflitos'])
    @relatorio['conflitos_total'] += conflitos.size
    @relatorio['conflitos'] = (@relatorio['conflitos'] + conflitos).first(MAX_CONFLITOS)
  end
end
