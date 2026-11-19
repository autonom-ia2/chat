# A medição de uso da carteira de seguros (E9, #2902): por conta e por período, SÓ CONTAGENS. Nenhuma coluna de pessoa,
# número de apólice, nome, documento ou valor em dinheiro sai daqui: cada número é um COUNT agrupado por um código nosso
# (origem, tipo do passo, motivo). Quem lê é a página do Super Admin (SuperAdmin::CarteiraMedidasController).
#
# O período é o mês corrente ou o anterior, no fuso da conta, o mesmo da medida das cotações
# (Autonomia::Insurance::Medida.fuso_de): o "mês" da corretora termina às 23h59 dela. Cada conta é lida no fuso dela,
# com as consultas dela (por account_id, nos índices que já existem), como a página das cotações faz.
#
# Os blocos:
# - seguros: os que estão na carteira (nem cancelados nem renovados, Carteira::Consulta::SEM_FIM_DE_LINHA) por origem,
#   os de outra corretora (`de_fora`) à parte, e os cancelados à parte. É a foto de agora, não do período;
# - renovações: as em aberto agora (Carteira::Consulta::EM_RENOVACAO, no dia de hoje da conta, como a aba Seguros) e as
#   fechadas no período (renovou; não renovou, por motivo);
# - cotação da renovação: os passos da história dos seguros no período, e o "não saiu" por motivo;
# - leitura de PDF: os lotes (carteira_leituras) por origem e os passos de PDF da história no período;
# - chaves: se a conta tem seguro e as chaves por conta da leitura de PDF e da cotação.
class Carteira::Medida
  ESTE_MES = 'este_mes'.freeze
  MES_PASSADO = 'mes_passado'.freeze
  PERIODOS = [ESTE_MES, MES_PASSADO].freeze
  PASSOS_DA_COTACAO = %w[cotacao_pedida proposta_pedida proposta_pronta proposta_enviada proposta_enviada_sozinha
                         proposta_nao_saiu].freeze
  NAO_SAIU = 'proposta_nao_saiu'.freeze
  PASSOS_DA_LEITURA = %w[chegou_pdf dados_lidos_pdf].freeze
  # O passo ou o desfecho gravado sem motivo.
  SEM_MOTIVO = 'sem_motivo'.freeze
  CHAVES = { leitura: Carteira::Leitor::Liberado, cotacao: Carteira::Cotacao::Liberada }.freeze
  # Os blocos que o total soma; as chaves viram quantas contas têm cada uma.
  BLOCOS = %i[seguros renovacoes cotacao leitura].freeze
  MOTIVO = Arel.sql("carteira_apolice_eventos.valores ->> 'motivo'")

  # O período pedido, ou o mês corrente quando o pedido não é um dos dois.
  def self.periodo(pedido)
    PERIODOS.include?(pedido) ? pedido : ESTE_MES
  end

  # Uma linha por conta que usa a carteira (tem seguro, tem leitura ou tem uma das chaves ligada) e o total delas.
  def self.por_conta(pedido)
    linhas = Account.where(id: contas_com_carteira).order(:id).map { |conta| new(conta, pedido).call }
    { linhas: linhas, total: total(linhas) }
  end

  def self.contas_com_carteira
    (Carteira::Apolice.distinct.pluck(:account_id) + Carteira::Leitura.distinct.pluck(:account_id) + contas_com_chave).uniq
  end

  # A regra de cada chave é a dela mesma (`para?`), lida da conta inteira: as chaves moram no jsonb interno da conta.
  def self.contas_com_chave
    Account.select(:id, :internal_attributes).find_each.select { |conta| CHAVES.values.any? { |chave| chave.para?(conta) } }
           .map(&:id)
  end

  # Soma, bloco a bloco, os números de todas as linhas; nil sem linha nenhuma.
  def self.total(linhas)
    return if linhas.empty?

    somados = linhas.map { |linha| linha.slice(*BLOCOS) }.reduce { |soma, linha| soma.deep_merge(linha) { |_, a, b| a + b } }
    somados.merge(contas: [:tem_seguro, *CHAVES.keys].index_with { |chave| linhas.count { |linha| linha[:chaves][chave] } })
  end

  def initialize(account, pedido = nil)
    @account = account
    @periodo = self.class.periodo(pedido)
    @fuso = Autonomia::Insurance::Medida.fuso_de(account)
    @janela = janela
  end

  def call
    { conta_id: @account.id, periodo: @periodo, fuso: @fuso, inicio: @janela.begin.to_date, fim: @janela.end.to_date,
      seguros: seguros, renovacoes: renovacoes, cotacao: cotacao, leitura: leitura, chaves: chaves }
  end

  private

  def janela
    agora = Time.current.in_time_zone(@fuso)
    inicio = @periodo == MES_PASSADO ? agora.prev_month.beginning_of_month : agora.beginning_of_month
    inicio..inicio.end_of_month
  end

  def apolices
    Carteira::Apolice.where(account_id: @account.id)
  end

  def seguros
    na_carteira = apolices.where(Carteira::Consulta::SEM_FIM_DE_LINHA)
    por_origem = na_carteira.where(de_fora: false).group(:origem).count
    { por_origem: Carteira::Apolice::ORIGENS.index_with { |origem| por_origem.fetch(origem, 0) },
      de_fora: na_carteira.where(de_fora: true).count, cancelados: apolices.where.not(cancelado_em: nil).count }
  end

  def renovacoes
    nao_renovou = por_motivo(apolices.where(nao_renovou_em: @janela).group(:motivo_nao_renovou).count)
    { em_aberto: apolices.where(Carteira::Consulta::EM_RENOVACAO, hoje: Carteira::Selo.hoje(@account)).count,
      renovadas: apolices.where(renovado_em: @janela).count, nao_renovadas: nao_renovou.values.sum,
      nao_renovadas_por_motivo: nao_renovou }
  end

  def cotacao
    passos = eventos(PASSOS_DA_COTACAO).group('carteira_apolice_eventos.tipo').count
    { passos: PASSOS_DA_COTACAO.index_with { |passo| passos.fetch(passo, 0) },
      nao_saiu_por_motivo: por_motivo(eventos([NAO_SAIU]).group(MOTIVO).count) }
  end

  def leitura
    lotes = Carteira::Leitura.where(account_id: @account.id, created_at: @janela).group(:origem).count
    passos = eventos(PASSOS_DA_LEITURA).group('carteira_apolice_eventos.tipo').count
    { lotes: Carteira::Leitura::ORIGENS.index_with { |origem| lotes.fetch(origem, 0) },
      passos: PASSOS_DA_LEITURA.index_with { |passo| passos.fetch(passo, 0) } }
  end

  def chaves
    { tem_seguro: apolices.exists? }.merge(CHAVES.transform_values { |chave| chave.para?(@account) })
  end

  # Os passos da história dos seguros desta conta no período. O evento não tem account_id: a conta vem da apólice.
  def eventos(tipos)
    Carteira::ApoliceEvento.joins(:apolice).where(carteira_apolices: { account_id: @account.id })
                           .where(tipo: tipos, quando: @janela)
  end

  # { motivo => quantos }, com o vazio somado em SEM_MOTIVO e só os motivos que aconteceram.
  def por_motivo(contagem)
    contagem.each_with_object(Hash.new(0)) { |(motivo, quantos), soma| soma[motivo.presence || SEM_MOTIVO] += quantos }
            .sort.to_h
  end
end
