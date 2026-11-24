# #3099: o teste das duas versões de um passo "mensagem" da automação: em que pé está, o bloco que o histórico mostra
# (ResultDuasVersoes.vue, `naAutomacao`) e a escolha da versão que fica.
#
# Estados (os da tela):
# - 'testando': cada pessoa recebe uma das duas. O teste fecha quando cada versão foi mandada MINIMO_POR_VERSAO vezes;
#   a hora de escolher é o fechamento mais a espera da regra;
# - 'esperando_voce': no "eu escolho", passou da hora e ninguém escolheu. Até alguém escolher, segue o sorteio;
# - 'escolhida': todo mundo recebe a vencedora.
#
#   { passo, estado, criterio, espera, faltam, escolhe_em (epoch), teste_desde (epoch), vencedora, escolhida_por,
#     escolhida_em (epoch), versoes: [{ numero, receberam, responderam, compraram, valor: [{ currency, cents }] | nil }] }
#
# O texto de cada versão a tela lê da receita (com os dados pelo nome do catálogo); o servidor não manda.
class Autonomia::Automacao::DuasVersoes::Teste
  attr_reader :linha

  # `linha`: a VersaoVencedora do passo. `passo`: o passo da versão ativa da automação, com `versoes`.
  def initialize(linha, passo, agora: Time.current)
    @linha = linha
    @passo = passo
    @agora = agora
  end

  def criterio = regra['criterio'].presence || 'respostas'

  def espera = (regra['espera'].presence || ::Autonomia::Automacao::DuasVersoes::REGRA::ESPERA_POR_CRITERIO.fetch(criterio, 4)).to_i

  def escolhe_em = numeros.fechou_em&.+(espera.hours)

  def estado
    return 'escolhida' if @linha.escolhida?

    hora = escolhe_em
    criterio == 'eu_escolho' && hora && hora <= @agora ? 'esperando_voce' : 'testando'
  end

  def payload(user:, account_user:)
    contas = numeros.por_versao(pipeline_ids: funis_visiveis(user, account_user), com_valor: Crm::ValorDeVenda.ve?(account_user))
    {
      passo: @passo['id'], estado: estado, criterio: criterio, espera: espera, faltam: numeros.faltam, escolhe_em: escolhe_em&.to_i,
      teste_desde: @linha.teste_desde&.to_i, vencedora: @linha.vencedora, escolhida_por: @linha.escolhida_por,
      escolhida_em: @linha.escolhida_em&.to_i, versoes: contas.each_with_index.map { |conta, indice| { numero: indice + 1, **conta } }
    }
  end

  # A escolha do cron (Autonomia::Automacao::EscolherVencedoraJob): na hora, a melhor pela régua da campanha; empate ou
  # poucas respostas, a versão 1. No "eu escolho" o cron não escolhe.
  def decidir!
    return false if @linha.escolhida? || criterio == 'eu_escolho'

    hora = escolhe_em
    return false if hora.nil? || hora > @agora

    melhor = ::CampaignJourney::DuasVersoes::Vencedora.melhor(*numeros.por_versao, criterio)
    escolher!(melhor || 1, por: melhor ? 'sistema' : 'empate')
  end

  # Uma vez só: true se escolheu agora; false se já havia vencedora (nada muda). `por`: 'sistema', 'empate' ou 'voce'.
  def escolher!(versao, por:, user: nil)
    @linha.with_lock do
      next false if @linha.escolhida?

      @linha.update!(vencedora: versao, escolhida_por: por, escolhida_por_user: user, escolhida_em: @agora)
      true
    end
  end

  private

  def regra = @passo['versoes'].to_h

  def numeros
    @numeros ||= ::Autonomia::Automacao::DuasVersoes::Numeros.new(@linha)
  end

  # Como o resto do histórico (ComprasDoHistorico): só os funis que a pessoa vê nos relatórios (#1148).
  def funis_visiveis(user, account_user)
    visible = Crm::Access::VisiblePipelines.new(user: user, account: @linha.account, account_user: account_user)
    visible.report_ids if visible.restricted?
  end
end
