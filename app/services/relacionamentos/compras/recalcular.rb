# Refaz o resumo de compras (Relacionamentos::Compra) de pessoas de uma conta, a partir dos cards ganhos, e o grupo de
# compra de cada uma (#3097). A compra é o card ganho num funil de Vender, inclusive o arquivado depois de ganho
# (Crm::Card.com_desfecho); a data é o closed_at do ganho. Pessoa que perdeu todas as compras (card reaberto, apagado,
# levado para outra pessoa) perde a linha.
#
# `contact_ids`: as pessoas a refazer; nil refaz a conta inteira (a rotina diária e o ajuste das faixas).
# `disparar`, quando o grupo muda, o gatilho "entrou no grupo de compra" (Gatilhos `contato.entrou_no_grupo_de_compra`):
#   - :venda — a mudança veio de uma venda (o card ganho ou desfeito): dispara também para quem ganha a linha agora
#     (a primeira compra põe a pessoa em "Comprou uma vez");
#   - :tempo — a rotina diária: dispara só para quem já tinha linha e mudou de grupo com o passar do tempo. Quem ganha
#     linha aqui é o preenchimento (ou um ganho que não passou pelo modelo) e já estava no grupo: não "entrou";
#   - false — o ajuste das faixas: o grupo muda, ninguém recebe mensagem por isso.
# "Nunca comprou" não dispara: nenhum gatilho o oferece.
#
# Duas execuções ao mesmo tempo na mesma pessoa (o card e a rotina) não quebram: a linha nova entra com ON CONFLICT DO
# NOTHING, e a próxima passada acerta o que ficou para trás.
class Relacionamentos::Compras::Recalcular
  GATILHO = 'contato.entrou_no_grupo_de_compra'.freeze
  REAL = 'BRL'.freeze
  LOTE = 1_000

  def initialize(account, contact_ids: nil, disparar: :venda)
    @account = account
    @contact_ids = contact_ids&.compact&.uniq
    @disparar = disparar
    @agora = Time.current
    @faixas = Relacionamentos::Compras::Faixas.da_conta(account)
  end

  def call
    return if @contact_ids&.empty?

    somas = somar
    existentes = linhas_existentes
    entraram = gravar(somas, existentes)
    apagar(existentes.keys - somas.keys)
    disparar(entraram)
  end

  private

  # { contact_id => atributos da linha }, numa leitura só dos cards ganhos, por pessoa e moeda.
  def somar
    ganhos.group(:contact_id, :currency)
          .pluck(:contact_id, :currency, Arel.sql('COUNT(*)'), Arel.sql('SUM(value_cents)'), Arel.sql('MIN(closed_at)'),
                 Arel.sql('MAX(closed_at)'))
          .group_by(&:first).transform_values { |moedas| atributos(moedas) }
  end

  def ganhos
    cards = Crm::Card.com_desfecho(:won).where(account_id: @account.id).where.not(contact_id: nil).where.not(closed_at: nil)
    @contact_ids ? cards.where(contact_id: @contact_ids) : cards
  end

  # `moedas`: as linhas da leitura de uma pessoa, [contact_id, moeda, quantas, total, primeira, última] por moeda.
  def atributos(moedas)
    por_moeda = moedas.map { |linha| da_moeda(linha) }.sort_by { |item| -item['total_cents'] }
    { quantas: por_moeda.sum { |item| item['quantas'] }, primeira_em: moedas.map(&:fifth).min, ultima_em: moedas.map(&:last).max,
      total_brl_cents: em_real(por_moeda), por_moeda: por_moeda }
  end

  def em_real(por_moeda)
    por_moeda.find { |item| item['moeda'] == REAL }&.fetch('total_cents') || 0
  end

  def da_moeda(linha)
    _contact_id, moeda, quantas, total = linha
    { 'moeda' => moeda, 'total_cents' => total.to_i, 'quantas' => quantas }
  end

  def linhas_existentes
    linhas = Relacionamentos::Compra.where(account_id: @account.id)
    linhas = linhas.where(contact_id: @contact_ids) if @contact_ids
    linhas.index_by(&:contact_id)
  end

  # Grava as linhas novas em lote e as que mudaram uma a uma. Devolve [[contact_id, grupo]] de quem entrou num grupo.
  def gravar(somas, existentes)
    novas = []
    entraram = somas.filter_map do |contact_id, atributos|
      linha = existentes[contact_id] || Relacionamentos::Compra.new(account_id: @account.id, contact_id: contact_id)
      linha.assign_attributes(atributos)
      grupo = Relacionamentos::Compras::Grupo.de(linha, @faixas, @agora)
      linha.assign_attributes(grupo: grupo, grupo_desde: @agora) if grupo != linha.grupo
      linha.new_record? ? novas << linha : (linha.save! if linha.changed?)
      [contact_id, grupo, linha.grupo_desde] if entrou?(linha, existentes.key?(contact_id))
    end
    inserir(novas)
    entraram
  end

  def entrou?(linha, existia)
    return false unless @disparar && linha.grupo_desde == @agora

    existia || @disparar == :venda
  end

  def inserir(novas)
    novas.each_slice(LOTE) do |lote|
      linhas = lote.map { |linha| linha.attributes.except('id').merge('created_at' => @agora, 'updated_at' => @agora) }
      # As linhas já passaram pelo serviço (as somas e o grupo); o lote é o preenchimento de uma conta inteira.
      Relacionamentos::Compra.insert_all(linhas, unique_by: :contact_id) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def apagar(contact_ids)
    Relacionamentos::Compra.where(account_id: @account.id, contact_id: contact_ids).delete_all if contact_ids.any?
  end

  # Só consulta os contatos quando há automação ligada com o gatilho; a Escuta confere o grupo escolhido de cada uma.
  def disparar(entraram)
    return if entraram.empty? || !::Autonomia::Automacao::Escuta.automacoes_do_gatilho(@account.id, GATILHO).exists?

    grupos = entraram.to_h { |contact_id, grupo, desde| [contact_id, [grupo, desde]] }
    @account.contacts.where(id: grupos.keys).find_each do |contato|
      grupo, desde = grupos.fetch(contato.id)
      marca = "#{GATILHO}:#{contato.id}:#{grupo}:#{desde.utc.iso8601(6)}"
      ::Autonomia::Automacao::Escuta.comecar(contato, GATILHO, evento: marca, dados: { 'grupo_de_compra' => grupo })
    end
  end
end
