# O que as duas abas da Lista nova de Relacionamentos têm em comum (#2894): conferir o pedido da tela, contar cada grupo,
# ordenar e paginar. Cada aba (ConsultaDePessoas, ConsultaDeEmpresas) diz a tabela, os grupos e quem a busca e os filtros
# deixam passar. A regra é a da demonstração da tela (relacionamentos/fonte/listaFonte.js e grupos.js).
class Relacionamentos::Consulta
  POR_PAGINA = 25
  # A última página que a lista aceita: 25 milhões de linhas puladas, que cabem com folga no OFFSET do banco (bigint).
  # Página maior responde 422 em vez de estourar a consulta.
  PAGINA_MAXIMA = 1_000_000
  # "Falou há pouco" vai até 30 dias exatos; "sumiu" começa depois disso e muda de grupo depois de 90 dias exatos.
  FALOU_HA_POUCO = 30.days
  SUMIU = 90.days
  ORDEM_PADRAO = 'ultima_conversa'.freeze

  # Por nome como a tela ordena, sem diferença de acento nem de maiúscula. O COLLATE "C" tira a collation do banco da
  # conta (ela muda de um ambiente para outro); nomes iguais desempatam pelo id.
  def self.por_nome(tabela)
    "#{SearchService::SemAcento.sql("#{tabela}.name")} COLLATE \"C\", #{tabela}.id"
  end

  def initialize(account, pedido)
    @account = account
    @pedido = pedido.to_h.with_indifferent_access
    @agora = Time.current
    conferir_pedido
  end

  # O número de cada grupo para a mesma busca e os mesmos filtros da lista (o grupo pedido não entra na conta).
  def contagens
    Relacionamentos::ContagemPorGrupo.call(consultados, grupos.transform_values { |condicao| com_os_cortes(condicao) })
  end

  def itens
    com_o_que_a_linha_usa(ordenados.offset((pagina - 1) * POR_PAGINA).limit(POR_PAGINA))
  end

  def total
    @total ||= do_grupo.count
  end

  def tem_mais?
    pagina * POR_PAGINA < total
  end

  private

  def do_grupo
    consultados.where(com_os_cortes(grupos.fetch(grupo)))
  end

  # O empate (mesma data, ou nunca conversou) sai pela ordem de chegada: sem desempate, a página 2 repetiria ou pularia gente.
  def ordenados
    do_grupo.order(Arel.sql(ordens.fetch(ordem)))
  end

  def ordens
    { 'ultima_conversa' => "#{tabela}.last_activity_at DESC NULLS LAST, #{tabela}.id",
      'nome' => self.class.por_nome(tabela),
      'mais_novos' => "#{tabela}.created_at DESC, #{tabela}.id" }
  end

  def com_os_cortes(condicao)
    ActiveRecord::Base.sanitize_sql_array([condicao, { falou_ha_pouco: @agora - FALOU_HA_POUCO, sumiu: @agora - SUMIU }])
  end

  def buscados(escopo, textos:, numeros:)
    Relacionamentos::Busca.new(@pedido[:busca]).aplicar(escopo, textos: textos, numeros: numeros)
  end

  # Sem grupo, vale o primeiro da aba ("todos", "todas"); sem ordem, a última conversa primeiro.
  def grupo
    @pedido[:grupo].presence || grupos.keys.first
  end

  def ordem
    @pedido[:ordem].presence || ORDEM_PADRAO
  end

  def pagina
    @pedido[:pagina].blank? ? 1 : Integer(@pedido[:pagina].to_s, 10, exception: false)
  end

  def conferir_pedido
    recusar("grupo desconhecido: #{grupo}") unless grupos.key?(grupo)
    recusar("ordem desconhecida: #{ordem}") unless ordens.key?(ordem)
    recusar("pagina inválida: #{@pedido[:pagina]}") unless pagina&.between?(1, PAGINA_MAXIMA)
  end

  def recusar(mensagem)
    raise Relacionamentos::PedidoInvalido, mensagem
  end
end
