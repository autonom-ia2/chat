# "Automações deste card" (#2499 F6.3): o que roda num card agora e o "Parar para este card".
#
# A lista são as execuções abertas com o card como alvo, de qualquer automação da conta: o passo em que cada uma está
# (o `cursor`, id do passo na receita da versão em que ela entrou), a espera e o que ela já fez neste card. Como no
# histórico da automação (Historico), sai só id de passo, hora e a receita para a tela fazer as frases; nunca texto de
# conversa (D8). A receita passa pela Versao#receita_para_tela de quem pede (a URL do webhook escondida, #2450).
#
# Só card aberto: ganho, perdido ou arquivado não tem automação de etapa rodando, e a tela não mostra a parte.
#
# Parar (P6, decidido pelo Rodrigo em 03/11): para só o que está rodando neste card, desta automação. Os outros cards
# seguem, e a automação continua ligada; o card que entrar de novo na etapa começa outra vez. Sem tabela de exclusão,
# então sem migration. Fecha como o Definicao#desligar!, só no card (Execucao.parar_por_fora!): a que esperava ganha o
# registro no passo da espera; a que estava no meio de uma rodada leva o porquê, para sozinha e registra lá.
#
# Para também o que a automação começou em outro registro por causa deste card (decisão do Rodrigo, 12/11): as filhas
# abertas do passo "em outro registro" (EmOutroRegistro) que nasceram de uma execução desta automação neste card, como
# a mensagem agendada para o contato indicado. Valem as filhas de qualquer vez dela no card, aberta ou já terminada: a
# mãe não espera as filhas. Tudo numa leitura travada só, com o mesmo motivo. As filhas de outro card não mudam.
class Autonomia::Automacao::NoCard
  Execucao = ::Autonomia::Automacao::Execucao
  Registro = ::Autonomia::Automacao::Registro
  MOTIVO = 'parada_no_card'.freeze

  def initialize(card:, account_user:)
    @card = card
    @account_user = account_user
  end

  def lista
    return [] unless @card.open?

    execucoes = abertas.includes(:automacao, :versao).order(:created_at, :id).to_a
    registros = Registro.where(execucao_id: execucoes.map(&:id)).order(:created_at, :id).group_by(&:execucao_id)
    execucoes.map { |execucao| para_tela(execucao, registros.fetch(execucao.id, [])) }
  end

  # Devolve quantas execuções fechou, filhas em outro registro incluídas (0 quando nada rodava desta automação neste card).
  def parar!(automacao)
    fechadas = Execucao.transaction { Execucao.parar_por_fora!(do_card_e_filhas(automacao), MOTIVO) }
    return 0 if fechadas.empty?

    ::Autonomia::Automacao::Cobertura.encerrar(fechadas)
    Execucao.where(id: fechadas).find_each { |execucao| ::Autonomia::Automacao::CampanhaDaOcorrencia.conferir_execucao(execucao) }
    fechadas.size
  end

  private

  def abertas = Execucao.abertas.where(account_id: @card.account_id, alvo: @card)

  # As execuções desta automação neste card e as filhas delas em outro registro, numa consulta só, sem trazer as mães
  # para o Ruby (o card pode ter muitas vezes da automação). A filha é achada pela marca do evento
  # (`em:<id da mãe>:...`, EmOutroRegistro.marca): o prefixo `em:` usa o índice (automacao_id, evento) com
  # text_pattern_ops (LIKE com diferença de maiúsculas, nunca ILIKE), e o id da mãe, o segundo pedaço da marca, é
  # comparado como texto com as execuções do card. Pedaço inteiro: a mãe 12 não leva a filha da 123.
  def do_card_e_filhas(automacao)
    da_automacao = Execucao.where(account_id: @card.account_id, automacao_id: automacao.id)
    no_card = da_automacao.where(alvo: @card)
    filhas = da_automacao.where(Execucao.arel_table[:evento].matches("#{::Autonomia::Automacao::EmOutroRegistro::MARCA}:%", nil, true))
                         .where("split_part(#{Execucao.table_name}.evento, ':', 2) IN (?)", no_card.select(Arel.sql('id::text')))
    no_card.or(filhas)
  end

  def para_tela(execucao, registros)
    {
      id: execucao.id, automacao_id: execucao.automacao_id, nome: execucao.automacao.nome, estado: execucao.estado,
      passo: execucao.cursor, comecou: execucao.created_at, receita: execucao.versao.receita_para_tela(@account_user),
      **::Autonomia::Automacao::Historico.espera(execucao, registros),
      feitos: feitos(execucao, registros)
    }
  end

  # O que já fez: os passos que deram certo. O registro da espera em curso não conta: ela ainda não acabou.
  def feitos(execucao, registros)
    registros.select { |registro| registro.resultado == 'ok' && !espera_em_curso?(execucao, registro) }
             .map { |registro| { passo: registro.passo, em: registro.created_at } }
  end

  def espera_em_curso?(execucao, registro) = execucao.estado == 'esperando' && registro.passo == execucao.cursor
end
