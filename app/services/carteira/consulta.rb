# A aba Seguros de Relacionamentos (E4, #2897): os seguros da conta, um por linha, com os grupos por vencimento, a busca
# (pessoa, empresa segurada, número da apólice e bem), os filtros (tipo e seguradora), a ordem e a página. Tudo no banco,
# como a lista de pessoas: a carteira não cabe inteira no navegador. Conferir o pedido, contar os grupos e paginar são
# os da lista (Relacionamentos::Consulta); aqui ficam a tabela, os grupos e as ordens.
#
# Os grupos de vencimento acumulam ("em até 30 dias" inclui quem vence amanhã) e só contam seguro que ainda vale: nem
# cancelado, nem vencido. O dia de hoje é o da conta (Carteira::Selo.hoje). "Em renovação" e "Parcela atrasada" não
# existem nesta entrega.
class Carteira::Consulta < Relacionamentos::Consulta
  ORDEM_DA_CARTEIRA = 'vence_primeiro'.freeze
  VENCE_EM = [7, 30, 90].freeze
  VALENDO = 'carteira_apolices.cancelado_em IS NULL AND carteira_apolices.fim_vigencia >= :hoje'.freeze
  GRUPOS = { 'todos' => 'TRUE' }.merge(
    VENCE_EM.to_h { |dias| ["vence_#{dias}_dias", "#{VALENDO} AND carteira_apolices.fim_vigencia <= :em_#{dias}_dias"] },
    'vencido' => 'carteira_apolices.cancelado_em IS NULL AND carteira_apolices.fim_vigencia < :hoje',
    'sem_telefone' => "COALESCE(contacts.phone_number, '') = ''"
  ).freeze
  # Quem ainda vale vem antes, do que termina mais cedo ao mais tarde; depois os outros, do que terminou há menos tempo
  # ao mais antigo. O id desempata: sem ele a página 2 repetiria ou pularia seguro.
  VENCE_PRIMEIRO = "(#{VALENDO}) DESC, CASE WHEN #{VALENDO} THEN carteira_apolices.fim_vigencia END ASC, " \
                   'carteira_apolices.fim_vigencia DESC, carteira_apolices.id'.freeze
  # O segurado é a empresa quando a apólice tem uma; senão, a pessoa.
  SEGURADO = 'COALESCE(companies.name, contacts.name)'.freeze
  TEXTOS = ['contacts.name', 'companies.name', 'carteira_apolices.numero', 'carteira_apolices.numero_chave', 'carteira_apolices.bem'].freeze
  NUMEROS = ['carteira_apolices.numero'].freeze
  # O que a linha de um seguro lê além da apólice (Carteira::Apresentacao): a pessoa com a foto, a empresa, a planilha
  # de onde veio e se tem PDF. Um Hash só, como o da lista de pessoas: é o formato que o preload recebe num argumento.
  O_QUE_A_LINHA_USA = { company: {}, campaign_import: {}, contact: { avatar_attachment: :blob }, pdf_attachment: :blob }.freeze

  # O que as ações em grupo leem da pessoa de cada seguro marcado.
  DA_PESSOA = %i[id name phone_number blocked opted_out_at].freeze

  def self.base(account)
    Carteira::Apolice.where(account_id: account.id).joins(:contact).left_joins(:company)
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

  def grupos
    GRUPOS
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
    buscados(self.class.base(@account), textos: TEXTOS, numeros: NUMEROS).where(do_tipo).where(da_seguradora)
  end

  def com_o_que_a_linha_usa(seguros)
    seguros.preload(O_QUE_A_LINHA_USA)
  end

  # As datas de corte de cada grupo, no dia de hoje da conta.
  def com_os_cortes(condicao)
    ActiveRecord::Base.sanitize_sql_array([condicao, cortes])
  end

  def cortes
    @cortes ||= { hoje: hoje }.merge(VENCE_EM.to_h { |dias| [:"em_#{dias}_dias", hoje + dias] })
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

  def conferir_pedido
    super
    recusar('tipo desconhecido') unless filtro(:tipo).nil? || Carteira::Apolice::TIPOS.include?(filtro(:tipo))
  end
end
