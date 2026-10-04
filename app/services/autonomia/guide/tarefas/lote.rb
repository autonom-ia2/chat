# UM lote de uma tarefa longa (#936): até 25 itens ou cerca de 15 s, como uma `Execucao` do diário.
#
# O resultado do item é gravado na mesma transação que as mudanças anotadas dele (`Diario.gravando`
# com `ao_persistir`): o lote que morre no meio não deixa item feito sem desfazer, e o item `feito`
# nunca repete. Entre um item e outro o lote confere se a pessoa pausou ou cancelou.
#
# Depois do lote, a tarefa para sozinha quando: é o primeiro lote (pausa de segurança), as falhas
# passam de 20%, ficou pendência sem desfazer, saiu mensagem da conta, o custo passou do teto, a
# cota do Jev acabou ou o dono deixou de administrar. Cada parada leva o motivo.
class Autonomia::Guide::Tarefas::Lote
  Tarefa = ::Autonomia::Guide::Tarefa
  Item = ::Autonomia::Guide::TarefaItem
  TAMANHO = 25
  PRAZO = 15.0
  MAX_FALHAS = 0.2
  # Quanto depois do lote uma mensagem ainda conta como dele: a automação roda num job.
  JANELA_DE_MENSAGENS = 60.seconds
  CONTINUAR = :continuar
  PARAR = :parar

  def initialize(tarefa)
    @tarefa = tarefa
    @receita = ::Autonomia::Guide::Tarefas::Receita.new(tarefa.receita)
    @contexto = ::Autonomia::Guide::Contexto.new(account: tarefa.account, user: tarefa.user)
  end

  # -> CONTINUAR (há mais a fazer) ou PARAR (parou, terminou ou falhou; o motivo está na tarefa).
  def rodar
    return falhar('receita_mudou') unless @tarefa.receita_intacta?

    motivo = motivo_antes
    return pausar(motivo) if motivo

    itens = @tarefa.itens.pendentes.limit(@tarefa.lote_tamanho).to_a
    return concluir if itens.empty?

    executar_lote(itens)
  end

  private

  def motivo_antes
    return 'admin' unless @contexto.administrador?

    anterior = @tarefa.execucoes.order(:id).last
    'mensagens' if anterior && @tarefa.mensagem_saiu?(anterior.created_at, anterior.updated_at + JANELA_DE_MENSAGENS)
  end

  def executar_lote(itens)
    inicio = Time.current
    execucao = ::Autonomia::Guide::Execucao.create!(account: @tarefa.account, user: @tarefa.user, tarefa: @tarefa)
    preparo = ::Autonomia::Guide::Tarefas::Preparo.new(contexto: @contexto, receita: @receita)
    preparados = preparo.preparar(itens.map(&:record_id), prazo: relogio + PRAZO)
    contagem = executar(preparados, itens.index_by(&:record_id), execucao)
    depois(execucao, inicio, contagem, preparo.custo)
  rescue ::Autonomia::Guide::Tarefas::Preparo::CotaEsgotada
    descartar_vazia(execucao)
    pausar('cota_jev')
  rescue ::Autonomia::Guide::Tarefas::Gerador::Falhou
    descartar_vazia(execucao)
    pausar('gerar_falhou')
  end

  def executar(preparados, itens, execucao)
    preparados.each_with_object(Hash.new(0)) do |preparado, contagem|
      break contagem unless rodando?

      contagem[executar_um(preparado, itens.fetch(preparado.id), execucao)] += 1
      @tarefa.update_columns(batimento_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def executar_um(preparado, item, execucao)
    if preparado.motivo
      item.concluir!(Item::PULADO, preparado.motivo)
      return Item::PULADO
    end

    aplicar(preparado, item, execucao)
  rescue StandardError => e
    # O item que já ficou `feito` junto com as mudanças continua feito; só o que não chegou lá falha.
    execucao.reload
    return item.status unless item.reload.status == Item::PENDENTE

    item.concluir!(Item::FALHOU, e.is_a?(::Autonomia::Guide::Acoes::Recusada) ? e.message : e.class.name)
    Item::FALHOU
  end

  def aplicar(preparado, item, execucao)
    acao = @receita.acao
    @contexto.acoes.conferir!(acao, preparado.dados)
    concluir = ->(resultado) { item.concluir!(resultado.ok ? Item::FEITO : Item::FALHOU, resultado.ok ? nil : resultado.mensagem) }
    resultado = ::Autonomia::Guide::Diario.gravando(execucao, execucao.passos.size, ao_persistir: concluir) do
      @contexto.acoes.executar(acao, preparado.dados)
    end
    frase = "#{@receita.descricao} (#{::Autonomia::Guide::Tarefas::Preparo.rotulo(preparado.registro, preparado.id)})"
    execucao.registrar_passo(acao: acao, frase: frase, feito: resultado.ok, registro: resultado.registro)
    item.status
  end

  def depois(execucao, inicio, contagem, custo)
    @tarefa.update!(lotes: @tarefa.lotes + 1, custo: @tarefa.custo + custo, batimento_em: Time.current,
                    expira_em: [@tarefa.expira_em, execucao.expira_em].max)
    @tarefa.contar!
    guardar_canario(execucao, contagem) if @tarefa.lotes == 1
    pausar_ou_seguir(motivo_depois(execucao.reload, inicio, contagem))
  end

  def motivo_depois(execucao, inicio, contagem)
    return 'pendencia' if execucao.pendencias.any?
    return 'mensagens' if @tarefa.mensagem_saiu?(inicio, Time.current)
    return 'falhas' if contagem[Item::FALHOU] > contagem.values.sum * MAX_FALHAS
    return 'custo' if @tarefa.custo > @tarefa.teto_custo

    'canario' if @tarefa.lotes == 1 && @tarefa.itens.pendentes.exists?
  end

  def pausar_ou_seguir(motivo)
    return PARAR unless rodando?
    return pedir_ok if motivo == 'canario'
    return pausar(motivo) if motivo
    return concluir unless @tarefa.itens.pendentes.exists?

    CONTINUAR
  end

  # O que o primeiro lote mudou, por tabela, e os jobs que ele deixou na fila: é o que a pessoa
  # confere antes de seguir.
  def guardar_canario(execucao, contagem)
    @tarefa.update!(canario: { 'tabelas' => execucao.mudancas.reorder(nil).group(:tabela).count, 'jobs' => execucao.reload.jobs,
                               'itens' => contagem.values.sum })
  end

  def descartar_vazia(execucao)
    return false unless execucao&.passos&.empty?

    execucao.destroy!
    true
  end

  def pedir_ok
    @tarefa.update_columns(status: Tarefa::CANARIO, updated_at: Time.current) if rodando? # rubocop:disable Rails/SkipsModelValidations
    PARAR
  end

  def pausar(motivo)
    @tarefa.mudar!('pausar', motivo_pausa: motivo)
    PARAR
  end

  def falhar(motivo)
    Tarefa.where(id: @tarefa.id, status: Tarefa::ANDANDO)
          .update_all(status: Tarefa::FALHOU, motivo_pausa: motivo, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    PARAR
  end

  def concluir
    Tarefa.where(id: @tarefa.id, status: Tarefa::ANDANDO)
          .update_all(status: Tarefa::CONCLUIDA, motivo_pausa: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    @tarefa.reload.contar!
    PARAR
  end

  def rodando?
    Tarefa.where(id: @tarefa.id).pick(:status) == Tarefa::RODANDO
  end

  def relogio
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
