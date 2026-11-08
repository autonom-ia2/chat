# card.recorrente e contato.recorrente (#2635, G7): na ocorrência (todo dia, toda semana ou todo mês, numa hora cheia,
# no fuso da conta), cada card ou contato da seleção abre uma execução, uma vez por ocorrência. conta.recorrente abre
# uma execução por ocorrência, na própria conta.
#
# A ocorrência é a última que já passou, hoje ou ontem (a janela é de 1 dia: uma pane longa não roda depois). Ela é
# montada pelo dia e pela hora no fuso (TimeZone#local), nunca somando horas: na troca do horário de verão a hora
# ambígua dá sempre o mesmo instante, e a marca (em UTC) não repete. Ligar não age no passado: a ocorrência anterior a
# ligar (ou a salvar a versão ligada) não roda. O dia do mês que não existe (31 em abril) cai no último dia.
# A frequência uma_vez (#2681, "quinta antes da Black Friday, 9h") tem uma ocorrência só, na data (AAAA-MM-DD) e na
# hora: a marca da ocorrência impede repetir, e depois dela não há outra.
#
# Os alvos saem em lotes de ids (`lotes`): o TempoDaAutomacaoJob enfileira um RecorrenteLoteJob por lote, e a fila não
# trava numa seleção grande. Sem teto de quantidade: 25 mil contatos numa etiqueta é uso, não defeito.
class Autonomia::Automacao::Tempo::Recorrente
  LOTE = 500

  def initialize(definicao:, gatilho:, agora:)
    @definicao = definicao
    @gatilho = gatilho
    @agora = agora
  end

  # Cada lote de ids da seleção, com a ocorrência; nada quando não há ocorrência a rodar. O da conta é um lote só, com
  # a própria conta.
  def lotes
    instante = ocorrencia
    return unless instante
    return yield([@definicao.account_id], instante) if ::Autonomia::Automacao::Gatilhos.da_conta?(@gatilho['tipo'])

    selecao.de_quem_ligou(::Autonomia::Automacao::Acesso.new(@definicao)).in_batches(of: LOTE) { |lote| yield lote.ids, instante }
  end

  def ocorrencia
    ultima = dias_da_janela.lazy.filter_map { |dia| instante(dia) if dia?(dia) }.find { |candidata| candidata <= @agora }
    return if ultima.nil? || ultima <= @agora - ::Autonomia::Automacao::Tempo::JANELA
    return if ultima < ::Autonomia::Automacao::Tempo.ligada_desde(@definicao)

    ultima
  end

  private

  def selecao = ::Autonomia::Automacao::Tempo::Selecao.new(@definicao.account, @gatilho)

  def fuso = (@fuso ||= ::Autonomia::Automacao::Tempo.fuso(@definicao.account))

  # Hoje e ontem, no fuso da conta.
  def dias_da_janela
    hoje = @agora.in_time_zone(fuso).to_date
    [hoje, hoje - 1]
  end

  def instante(dia) = fuso.local(dia.year, dia.month, dia.day, @gatilho['hora'].to_i)

  def dia?(dia)
    case @gatilho['frequencia']
    when 'semanal' then dia.wday == @gatilho['dia_da_semana'].to_i
    when 'mensal' then dia.day == [@gatilho['dia_do_mes'].to_i, dia.end_of_month.day].min
    when 'uma_vez' then dia.iso8601 == @gatilho['data']
    else true
    end
  end
end
