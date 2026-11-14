# Os resultados das renovações da conta (E5, #2898): dos seguros que terminaram nos últimos 30, 90 e 365 dias, quantos
# renovaram, quantos não, por que não, e os mesmos números por tipo, por seguradora e por quem cuida. Mais quantos
# vencem nos próximos 30 dias. O dia de hoje é o da conta (Carteira::Selo.hoje).
#
# As contas:
# - `venceram`: seguros não cancelados cujo fim caiu no período (de N dias atrás até ontem). O cancelado não entra: ele
#   não chegou ao fim;
# - `renovou`: desses, os que têm "Renovou";
# - `naoRenovou`: o resto, tenha alguém dito "não renovou" ou não. É o mesmo conjunto do grupo "Não renovaram nos
#   últimos N dias" da aba Seguros (Carteira::Consulta::TEMPORARIOS), para a tela e a lista mostrarem os mesmos seguros;
# - `motivos`: os que não renovaram, por motivo. Vêm sempre todos os motivos, mais `sem_motivo` (ninguém disse por quê:
#   o card foi fechado no quadro sem motivo, ou o seguro só venceu);
# - `recortes`: só as linhas que têm algum seguro no período, das que mais venceram para as que menos. "Quem cuida" é
#   o dono do card de renovação HOJE; seguro sem card, ou com card sem dono, não entra nesse recorte. Se o card trocou
#   de dono depois de fechado, o número vai para o dono novo. Com quem o card nasceu fica na história do seguro
#   (`valores.cuida_id` do passo `renovacao_card_nasceu`), para o dia em que o recorte precisar de quem cuidava na época.
#
# Os totais, os motivos e os recortes por tipo e por seguradora são dado da carteira: vão para quem vê contatos. O
# recorte por quem cuida é desempenho de cada pessoa, e mostra o dono de card de funil que quem pede pode não abrir: é
# relatório, e só vai para quem vê os relatórios (ReportPolicy#view?: administrador ou a chave `report_manage`). Para os
# outros a chave `cuida` nem vem.
#
# Só números, nenhum dado de cliente. Até cinco consultas, qualquer que seja o tamanho da carteira: os três períodos
# saem juntos, um COUNT(*) FILTER por número.
class Carteira::Renovacao::Resultados
  PERIODOS = Carteira::Consulta::NAO_RENOVARAM_EM
  SEM_MOTIVO = 'sem_motivo'.freeze
  MOTIVOS = (Carteira::Apolice::MOTIVOS_DE_NAO_RENOVAR + [SEM_MOTIVO]).freeze
  RENOVOU = 'carteira_apolices.renovado_em IS NOT NULL'.freeze
  NAO_RENOVOU = 'carteira_apolices.renovado_em IS NULL'.freeze
  NOME_DA_SEGURADORA = 'MIN(carteira_apolices.seguradora COLLATE "C")'.freeze
  # [venceram, renovou] de cada linha de um recorte.
  DA_LINHA = [nil, RENOVOU].freeze

  # quem: o contexto de quem pede, como o Pundit o recebe ({ user:, account:, account_user: }).
  def initialize(account, quem: nil)
    @account = account
    @quem = quem
    @hoje = Carteira::Selo.hoje(account)
  end

  def call
    totais = venceram.pick(*colunas(do_total)).each_slice(do_total.size).to_a
    recortes = { tipo: recorte(:tipo, venceram.group(:tipo), 'carteira_apolices.tipo'),
                 seguradora: recorte(:nome, venceram.group(:seguradora_chave), NOME_DA_SEGURADORA) }.merge(de_quem_cuida)
    periodos = PERIODOS.each_with_index.map do |dias, indice|
      periodo(dias, totais[indice], recortes.transform_values { |linhas| linhas[indice] })
    end
    { periodos: periodos, vencem30: vencem_em_30_dias }
  end

  private

  def de_quem_cuida
    return {} unless @quem.present? && Pundit.policy!(@quem, :report).view?

    { cuida: recorte(:nome, venceram.joins(crm_card: :owner).group('users.id'), 'MIN(users.name)') }
  end

  # Tudo que terminou no período mais longo; cada número filtra o período dele.
  def venceram
    Carteira::Apolice.where(account_id: @account.id, cancelado_em: nil, fim_vigencia: (@hoje - PERIODOS.max)...@hoje)
  end

  # As condições de um número de cada coisa contada no total: venceram, renovou e cada motivo.
  def do_total
    @do_total ||= DA_LINHA + MOTIVOS.map { |motivo| "#{NAO_RENOVOU} AND #{do_motivo(motivo)}" }
  end

  def do_motivo(motivo)
    return 'carteira_apolices.motivo_nao_renovou IS NULL' if motivo == SEM_MOTIVO

    ActiveRecord::Base.sanitize_sql_array(['carteira_apolices.motivo_nao_renovou = ?', motivo])
  end

  # Para cada período, um COUNT(*) FILTER de cada condição, na ordem dos períodos.
  def colunas(condicoes)
    PERIODOS.flat_map do |dias|
      no_periodo = ActiveRecord::Base.sanitize_sql_array(['carteira_apolices.fim_vigencia >= ?', @hoje - dias])
      condicoes.map { |condicao| Arel.sql("COUNT(*) FILTER (WHERE #{[no_periodo, condicao].compact.join(' AND ')})") }
    end
  end

  def periodo(dias, total, recortes)
    venceu, renovou, *por_motivo = total
    { dias: dias, venceram: venceu, renovou: renovou, naoRenovou: venceu - renovou,
      motivos: MOTIVOS.zip(por_motivo).map { |motivo, quantos| { motivo: motivo, quantos: quantos } }, recortes: recortes }
  end

  # As linhas de um recorte em cada período: [[linhas de 30], [de 90], [de 365]].
  def recorte(chave, agrupados, nome)
    linhas = agrupados.pluck(Arel.sql(nome), *colunas(DA_LINHA))
    PERIODOS.each_index.map do |indice|
      do_periodo = linhas.map { |nome_da_linha, *numeros| [nome_da_linha, *numeros.each_slice(DA_LINHA.size).to_a[indice]] }
      das_que_mais_venceram(do_periodo).map { |nome_da_linha, venceu, renovou| { chave => nome_da_linha }.merge(venceram: venceu, renovou: renovou) }
    end
  end

  # Só as linhas com algum seguro no período; no empate, pelo nome.
  def das_que_mais_venceram(linhas)
    linhas.select { |_nome, venceu, _renovou| venceu.positive? }.sort_by { |nome, venceu, _renovou| [-venceu, nome.to_s] }
  end

  def vencem_em_30_dias
    Carteira::Apolice.where(account_id: @account.id)
                     .where(Carteira::Consulta::GRUPOS.fetch('vence_30_dias'), hoje: @hoje, em_30_dias: @hoje + 30).count
  end
end
