# #2933 — "Usar outra automação": a automação marcada como bloco (`autonomia_automacoes.bloco`) não tem gatilho próprio
# e só roda quando outra a usa. Muda num lugar, vale para todas as que usam ela.
#
# O passo "usar_bloco" abre uma execução própria do bloco (a "execução do bloco"), no mesmo alvo, e espera ela terminar
# para seguir (BlocoNoExecutor). A execução do bloco:
# - é marcada pelo `evento` (`bloco:<mãe>:<vez>:<passo>`): a vez separa o mesmo passo rodado de novo num laço do
#   "decidir"; o índice único (automacao_id, evento) garante uma execução só por chamada;
# - é `paralela`: o mesmo bloco pode rodar ao mesmo tempo no mesmo alvo para duas automações diferentes;
# - herda a cadeia e a profundidade da mãe (D6), e roda na versão do bloco em que entrou (D10);
# - age como quem ligou a automação de cima (a dona, Execucao#dona): a chave de automações, o alcance, o "ligada" e a
#   pausa são dela. O bloco nunca é ligado sozinho, então quem o montou não empresta as permissões a ninguém. E quem
#   muda o bloco não ganha as de quem ligou: a versão nova pausa as automações ligadas que chegam nele, menos as que a
#   própria pessoa ligou (Definicao#salvar_versao!), a mesma regra de quem salva uma automação ligada por outra pessoa;
# - acorda a mãe quando termina (`acordar_mae`): a mãe confere de novo também uma vez por dia (CONFERENCIA), contra
#   defeito.
#
# Bloco que chama bloco vale até PROFUNDIDADE níveis, sem laço (A usa B, que usa A): o salvar recusa pela cadeia das
# versões ativas (`conferir_cadeia`) e a rodada confere de novo pelas execuções de cima (`acima`), porque o bloco pode
# mudar depois de a mãe salvar.
module Autonomia::Automacao::Bloco
  TIPO = 'usar_bloco'.freeze
  MARCA = 'bloco'.freeze
  PROFUNDIDADE = 3
  CONFERENCIA = 1.day
  # Onde a mãe guarda a execução do bloco que chamou, na própria execução (Execucao#textos), até terminar.
  CHAVE = 'bloco:'.freeze

  module_function

  def do_tipo?(passo) = passo['tipo'] == TIPO

  def marca(mae, passo_id, vez) = [MARCA, mae.id, vez, passo_id].join(':')

  # [id da mãe, id do passo] da execução de um bloco; nil nas outras. O id do passo vai por último: ele pode ter ":".
  def da(execucao)
    prefixo, mae_id, _vez, passo_id = execucao&.evento.to_s.split(':', 4)
    [mae_id.to_i, passo_id] if prefixo == MARCA && passo_id.present?
  end

  # A mãe de qualquer execução filha: a do bloco, a da lista (#2932) ou a do "em outro registro" (G18), sempre na conta
  # dela; nil na execução de cima. O bloco pode ter um "para cada" ou um "em outro registro" dentro: as filhas deles
  # também agem como a dona de cima.
  def mae(execucao)
    mae_id, = da(execucao) || ::Autonomia::Automacao::RepetirLista.da(execucao) || ::Autonomia::Automacao::EmOutroRegistro.da(execucao)
    mae_id && ::Autonomia::Automacao::Execucao.find_by(id: mae_id, account_id: execucao.account_id)
  end

  # Contra defeito: nenhuma cadeia de mães de verdade chega perto disto (blocos até PROFUNDIDADE, uma lista ou um "em
  # outro registro" no meio).
  ACIMA_MAXIMO = 10

  # As execuções acima desta, da mãe direta até a de cima de todas.
  def acima(execucao)
    lista = []
    atual = execucao
    while lista.size < ACIMA_MAXIMO && (de_cima = mae(atual))
      lista << de_cima
      atual = de_cima
    end
    lista
  end

  # Em quantos blocos esta execução já está: a dela, se for de bloco, e as de cima.
  def niveis(execucao) = [execucao, *acima(execucao)].count { |uma| da(uma) }

  # A automação de quem valem as permissões e o "ligada": a de cima de todas. Nas execuções que não são de bloco, a
  # própria.
  def dona(execucao) = (acima(execucao).last || execucao).automacao

  # O bloco terminou: a mãe que espera nele acorda na próxima varredura, em vez de esperar a conferência do dia.
  def acordar_mae(execucao)
    mae_id, passo_id = da(execucao)
    return unless mae_id

    agora = Time.current
    ::Autonomia::Automacao::Execucao.where(id: mae_id, account_id: execucao.account_id, estado: 'esperando', cursor: passo_id)
                                    .update_all(due_at: agora, updated_at: agora) # rubocop:disable Rails/SkipsModelValidations
  end

  # Ao salvar a versão de `automacao` (Versao#receita_executavel) e ao ligá-la: um bloco usado na receita leva de volta a
  # ela, pela cadeia das versões ativas? Só a Versao sabe qual automação está sendo salva; o resto da cadeia o passo
  # confere (PassoUsarBloco).
  def laco_ao_salvar(receita, automacao)
    return [] unless automacao&.persisted?

    blocos = ::Autonomia::Automacao::Definicao.where(account_id: automacao.account_id, bloco: true, id: usados(receita))
    blocos.filter_map do |bloco|
      problema, = conferir_cadeia(bloco, automacao.account, salvando: automacao.id)
      I18n.t('autonomia.automacao.receita.bloco.laco_volta', bloco: bloco.nome) if problema == :laco
    end
  end

  # As automações ligadas da conta que chegam a `bloco` pela versão ativa: direto, ou por outro bloco que usa ele.
  def ligadas_que_usam(bloco)
    conta = bloco.account
    ::Autonomia::Automacao::Definicao.where(account_id: conta.id, ativa: true).includes(:versao_ativa).select do |automacao|
      usados = ::Autonomia::Automacao::Definicao.where(account_id: conta.id, bloco: true, id: usados(automacao.versao_ativa&.receita))
      usados.any? { |usado| conferir_cadeia(usado, conta).last.include?(bloco) }
    end
  end

  # As que pausam quando `pessoa` salva uma versão nova do bloco (Definicao#salvar_versao!): as ligadas que chegam nele e
  # que outra pessoa ligou.
  def ligadas_por_outras(bloco, pessoa)
    ligadas_que_usam(bloco).reject { |automacao| pessoa.present? && automacao.ligada_por_id == pessoa.id }
  end

  # Os nomes das automações ligadas da conta que usam `bloco` na versão ativa.
  def usado_por(bloco)
    ::Autonomia::Automacao::Definicao.where(account_id: bloco.account_id, ativa: true).includes(:versao_ativa).filter_map do |automacao|
      automacao.nome if usados(automacao.versao_ativa&.receita).include?(bloco.id)
    end
  end

  # O tipo do alvo em que o bloco roda: o do gatilho da versão ativa dele (o gatilho não dispara: só diz o alvo).
  def alvo(bloco) = ::Autonomia::Automacao::Gatilhos.alvo(bloco.versao_ativa&.receita&.dig('gatilho', 'tipo'))

  # Os ids dos blocos que a receita usa, em qualquer ramo.
  def usados(receita)
    ::Autonomia::Automacao::Receita.new(receita.to_h, conta: nil, account_user: nil).passos.select { |passo| do_tipo?(passo) }
                                   .filter_map { |passo| passo['bloco_id'] }
  end

  # [problema ou nil, os blocos alcançados]: `bloco` e os que ele usa, em profundidade, pelas versões ativas. O problema é
  # :laco quando o caminho volta a uma automação dele (ou à que está sendo salva, `salvando`), :fundo quando passa de
  # PROFUNDIDADE.
  def conferir_cadeia(bloco, conta, salvando: nil)
    alcancados = []
    problema = visitar(bloco, conta, [salvando].compact, 1, alcancados)
    [problema, alcancados]
  end

  def visitar(bloco, conta, caminho, nivel, alcancados)
    return :laco if caminho.include?(bloco.id)
    return :fundo if nivel > PROFUNDIDADE

    alcancados << bloco unless alcancados.include?(bloco)
    filhos = ::Autonomia::Automacao::Definicao.where(account_id: conta.id, bloco: true, id: usados(bloco.versao_ativa&.receita))
    filhos.each do |filho|
      problema = visitar(filho, conta, caminho + [bloco.id], nivel + 1, alcancados)
      return problema if problema
    end
    nil
  end
end
