# A aba Seguros de Relacionamentos (E4, #2897): os seguros da conta, um por linha, com os grupos por vencimento, a busca
# (pessoa, empresa segurada, número da apólice e bem), os filtros (tipo e seguradora), a ordem e a página. Tudo no banco,
# como a lista de pessoas: a carteira não cabe inteira no navegador. Conferir o pedido, contar os grupos e paginar são
# os da lista (Relacionamentos::Consulta); aqui ficam a tabela, os grupos e as ordens.
#
# Os grupos de vencimento acumulam ("em até 30 dias" inclui quem vence amanhã) e só contam seguro que ainda vale: nem
# cancelado, nem renovado, nem vencido. O dia de hoje é o da conta (Carteira::Selo.hoje). "Parcela atrasada" não existe
# nesta entrega.
#
# Com a renovação (E5, #2898): o grupo "Em renovação" (a mesma regra do selo, Carteira::Selo, só com as colunas da
# apólice), o filtro "quem cuida" (o dono do card de renovação, só entre os cards que quem pede enxerga no quadro) e os
# grupos temporários "Não renovaram nos últimos N dias", que só existem quando a tela de resultados leva até eles:
# terminaram nesse período sem renovar.
class Carteira::Consulta < Relacionamentos::Consulta
  ORDEM_DA_CARTEIRA = 'vence_primeiro'.freeze
  VENCE_EM = [7, 30, 90].freeze
  NAO_RENOVARAM_EM = [30, 90, 365].freeze
  SEM_FIM_DE_LINHA = 'carteira_apolices.cancelado_em IS NULL AND carteira_apolices.renovado_em IS NULL'.freeze
  VALENDO = "#{SEM_FIM_DE_LINHA} AND carteira_apolices.fim_vigencia >= :hoje".freeze
  VENCIDO = "#{SEM_FIM_DE_LINHA} AND carteira_apolices.fim_vigencia < :hoje".freeze
  COM_RENOVACAO_ABERTA = 'carteira_apolices.crm_card_id IS NOT NULL AND carteira_apolices.nao_renovou_em IS NULL ' \
                         'AND carteira_apolices.renovacao_card_removido_em IS NULL'.freeze
  EM_RENOVACAO = "#{VALENDO} AND #{COM_RENOVACAO_ABERTA}".freeze
  GRUPOS = { 'todos' => 'TRUE' }.merge(
    VENCE_EM.to_h { |dias| ["vence_#{dias}_dias", "#{VALENDO} AND carteira_apolices.fim_vigencia <= :em_#{dias}_dias"] },
    'em_renovacao' => EM_RENOVACAO, 'vencido' => VENCIDO, 'sem_telefone' => "COALESCE(contacts.phone_number, '') = ''"
  ).freeze
  TEMPORARIOS = NAO_RENOVARAM_EM.to_h do |dias|
    ["nao_renovaram_#{dias}", "#{VENCIDO} AND carteira_apolices.fim_vigencia >= :ha_#{dias}_dias"]
  end.freeze
  # Quem ainda vale vem antes, do que termina mais cedo ao mais tarde; depois os outros, do que terminou há menos tempo
  # ao mais antigo. O id desempata: sem ele a página 2 repetiria ou pularia seguro.
  VENCE_PRIMEIRO = "(#{VALENDO}) DESC, CASE WHEN #{VALENDO} THEN carteira_apolices.fim_vigencia END ASC, " \
                   'carteira_apolices.fim_vigencia DESC, carteira_apolices.id'.freeze
  # O segurado é a empresa quando a apólice tem uma; senão, a pessoa.
  SEGURADO = 'COALESCE(companies.name, contacts.name)'.freeze
  TEXTOS = ['contacts.name', 'companies.name', 'carteira_apolices.numero', 'carteira_apolices.numero_chave', 'carteira_apolices.bem'].freeze
  NUMEROS = ['carteira_apolices.numero'].freeze
  # O que a linha de um seguro lê além da apólice (Carteira::Apresentacao): a pessoa com a foto, a empresa, a planilha
  # de onde veio, se tem PDF, o card de renovação com o funil, a etapa e quem cuida, e a apólice que a renovou. Um
  # Hash só, como o da lista de pessoas: é o formato que o preload recebe num argumento.
  O_QUE_A_LINHA_USA = { company: {}, campaign_import: {}, contact: { avatar_attachment: :blob }, pdf_attachment: :blob,
                        crm_card: [:pipeline, :stage, :owner], apolice_nova: {} }.freeze

  # O que as ações em grupo leem da pessoa de cada seguro marcado.
  DA_PESSOA = %i[id name phone_number blocked opted_out_at].freeze

  def self.base(account)
    Carteira::Apolice.where(account_id: account.id).joins(:contact).left_joins(:company)
  end

  # quem: o contexto de quem pede, como o Pundit o recebe. Só o filtro "quem cuida" o usa (Carteira::CardsVisiveis).
  def initialize(account, pedido, quem: nil)
    @quem = quem
    super(account, pedido)
  end

  # A consulta inteira, para "Marcar todas as N": só o que as ações em grupo leem de cada seguro (a mensagem vai por pessoa).
  def todos
    ordenados.pluck('carteira_apolices.id', *DA_PESSOA.map { |campo| "contacts.#{campo}" }).map do |id, *da_pessoa|
      pessoa = DA_PESSOA.zip(da_pessoa).to_h
      { id: id, pessoaId: pessoa[:id], pessoa: pessoa.merge(opted_out_at: pessoa[:opted_out_at]&.to_i) }
    end
  end

  private

  def tabela
    'carteira_apolices'
  end

  # Os de sempre e, quando é ele o pedido, o temporário: ele entra na contagem só enquanto está na tela.
  def grupos
    GRUPOS.merge(TEMPORARIOS.slice(@pedido[:grupo].to_s))
  end

  def ordem
    @pedido[:ordem].presence || ORDEM_DA_CARTEIRA
  end

  def ordens
    { ORDEM_DA_CARTEIRA => com_os_cortes(VENCE_PRIMEIRO),
      'nome' => "#{SearchService::SemAcento.sql(SEGURADO)} COLLATE \"C\", carteira_apolices.id",
      'mais_novos' => 'carteira_apolices.inicio_vigencia DESC NULLS LAST, carteira_apolices.id' }
  end

  def consultados
    buscados(self.class.base(@account), textos: TEXTOS, numeros: NUMEROS).where(do_tipo).where(da_seguradora).where(de_quem_cuida)
  end

  def com_o_que_a_linha_usa(seguros)
    seguros.preload(O_QUE_A_LINHA_USA)
  end

  # As datas de corte de cada grupo, no dia de hoje da conta.
  def cortes
    @cortes ||= { hoje: hoje }.merge(VENCE_EM.to_h { |dias| [:"em_#{dias}_dias", hoje + dias] },
                                     NAO_RENOVARAM_EM.to_h { |dias| [:"ha_#{dias}_dias", hoje - dias] })
  end

  def hoje
    @hoje ||= Carteira::Selo.hoje(@account)
  end

  # Filtro vazio quer dizer "qualquer".
  def filtro(chave)
    @pedido.dig(:filtros, chave).presence
  end

  def do_tipo
    { tipo: filtro(:tipo) } if filtro(:tipo)
  end

  # Pela forma de comparação: "Seguradora Exemplo" e "SEGURADORA EXEMPLO" são a mesma seguradora.
  def da_seguradora
    { seguradora_chave: Carteira::Chave.seguradora(filtro(:seguradora)) } if filtro(:seguradora)
  end

  # "Quem cuida" é o dono do card de renovação que o seguro mostra (o tirado do quadro não conta). Só entre os cards que
  # quem pede enxerga no quadro: sem isto, filtrar pelo id de um colega contaria de que seguros ele cuida num funil
  # que a pessoa não abre.
  def de_quem_cuida
    return unless filtro(:cuida)

    cards = Carteira::CardsVisiveis.new(@quem).call.where(owner_id: quem_cuida).select(:id)
    { crm_card_id: cards, renovacao_card_removido_em: nil }
  end

  def quem_cuida
    Integer(filtro(:cuida).to_s, 10, exception: false)
  end

  def conferir_pedido
    super
    recusar('tipo desconhecido') unless filtro(:tipo).nil? || Carteira::Apolice::TIPOS.include?(filtro(:tipo))
    recusar('quem cuida desconhecido') unless filtro(:cuida).nil? || quem_cuida&.positive?
  end
end
