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
# Para também tudo o que a automação começou por causa deste card ("Cancela tudo", decisão do Rodrigo, 12/11): as
# filhas do passo "em outro registro" (EmOutroRegistro), como a mensagem agendada para o contato indicado, as do "fazer
# para cada um de uma lista" (RepetirLista) e as execuções dos blocos que ela usou (Bloco, de outra automação), e as
# filhas dessas, em quantos níveis houver. Valem as de qualquer vez dela no card, aberta ou já terminada: a mãe não
# espera as filhas da lista nem as do "em outro registro". Tudo numa leitura travada só, com o mesmo motivo. O que
# nasceu de outro card não muda.
class Autonomia::Automacao::NoCard
  Execucao = ::Autonomia::Automacao::Execucao
  Registro = ::Autonomia::Automacao::Registro
  Bloco = ::Autonomia::Automacao::Bloco
  MOTIVO = 'parada_no_card'.freeze
  # As marcas das filhas que ficam na automação da mãe; a do bloco (Bloco::MARCA) é de outra automação.
  MARCAS_DA_MESMA = [::Autonomia::Automacao::EmOutroRegistro::MARCA, ::Autonomia::Automacao::RepetirLista::MARCA].freeze

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

  # Devolve quantas execuções fechou, as que ela começou incluídas (0 quando nada rodava desta automação neste card).
  def parar!(automacao)
    fechadas = Execucao.transaction do
      Execucao.parar_por_fora!(Execucao.where(account_id: @card.account_id, id: do_card_e_descendentes(automacao)), MOTIVO)
    end
    return 0 if fechadas.empty?

    ::Autonomia::Automacao::Cobertura.encerrar(fechadas)
    Execucao.where(id: fechadas).find_each { |execucao| ::Autonomia::Automacao::CampanhaDaOcorrencia.conferir_execucao(execucao) }
    fechadas.size
  end

  private

  def abertas = Execucao.abertas.where(account_id: @card.account_id, alvo: @card)

  # Os ids das execuções desta automação neste card e de tudo o que elas começaram, nível a nível (uma mãe por vez não
  # cabe: o card pode ter muitas vezes da automação). A filha é achada pela marca do evento (`em:`, `lista:` ou
  # `bloco:<id da mãe>:...`): o id da mãe, o segundo pedaço da marca, é comparado como texto com os ids do nível de cima.
  # Pedaço inteiro: a mãe 12 não leva a filha da 123. Para no primeiro nível sem filha nova; o teto (Bloco::ACIMA_MAXIMO,
  # o mesmo da subida pelas mães) é só contra defeito.
  def do_card_e_descendentes(automacao)
    todas = Execucao.where(account_id: @card.account_id, automacao_id: automacao.id, alvo: @card).pluck(:id, :automacao_id).to_h
    nivel = todas
    Bloco::ACIMA_MAXIMO.times do
      break if nivel.empty?

      nivel = filhas_de(nivel).except(*todas.keys)
      todas = todas.merge(nivel)
    end
    todas.keys
  end

  # { id => automacao_id } das filhas das `maes` ({ id => automacao_id }). As do "em outro registro" e da lista são da
  # automação da mãe: o prefixo usa o índice (automacao_id, evento) com text_pattern_ops (LIKE com diferença de
  # maiúsculas, nunca ILIKE). A do bloco é de outra automação, e qual bloco não se sabe pela mãe (a marca de bloco pode
  # ser tirada depois): sem automacao_id, esse índice não serve, e a busca vai pela conta.
  def filhas_de(maes)
    evento = Execucao.arel_table[:evento]
    da_conta = Execucao.where(account_id: @card.account_id)
                       .where("split_part(#{Execucao.table_name}.evento, ':', 2) IN (?)", maes.keys.map(&:to_s))
    prefixos = MARCAS_DA_MESMA.map { |marca| "#{marca}:%" }
    da_mesma = da_conta.where(automacao_id: maes.values.uniq).where(evento.matches_any(prefixos, nil, true))
    de_bloco = da_conta.where(evento.matches("#{Bloco::MARCA}:%", nil, true))
    da_mesma.pluck(:id, :automacao_id).to_h.merge(de_bloco.pluck(:id, :automacao_id).to_h)
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
