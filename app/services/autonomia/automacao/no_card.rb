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
# então sem migration. Fecha como o Definicao#desligar!, só no card: a que esperava ganha o registro no passo da espera;
# a que estava no meio de uma rodada para sozinha e registra lá (Executor#parou_por_fora).
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

  # Devolve quantas execuções fechou (0 quando nada rodava desta automação neste card).
  def parar!(automacao)
    fechadas = Execucao.transaction { fechar(abertas.where(automacao_id: automacao.id), automacao) }
    return 0 if fechadas.empty?

    ::Autonomia::Automacao::Cobertura.encerrar(fechadas)
    Execucao.where(id: fechadas).find_each { |execucao| ::Autonomia::Automacao::CampanhaDaOcorrencia.conferir_execucao(execucao) }
    fechadas.size
  end

  private

  def abertas = Execucao.abertas.where(account_id: @card.account_id, alvo: @card)

  # Sem callback, como o desligar: a execução órfã não passa no `belongs_to`, e parar não pode falhar por ela.
  def fechar(escopo, automacao)
    esperando = escopo.where(estado: 'esperando').pluck(:id, :cursor)
    ids = escopo.pluck(:id)
    return [] if ids.empty?

    agora = Time.current
    Execucao.abertas.where(id: ids).update_all(estado: 'parada', travada_em: nil, finalizada_em: agora, updated_at: agora, # rubocop:disable Rails/SkipsModelValidations
                                               **Execucao::AO_TERMINAR)
    registrar(automacao, esperando, agora)
    ids
  end

  def registrar(automacao, esperando, agora)
    return if esperando.empty?

    linhas = esperando.map do |execucao_id, cursor|
      { account_id: @card.account_id, automacao_id: automacao.id, execucao_id: execucao_id, passo: cursor || 'inicio',
        resultado: 'pulado', motivo: MOTIVO, dados: {}, created_at: agora }
    end
    Registro.insert_all!(linhas) # rubocop:disable Rails/SkipsModelValidations
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
