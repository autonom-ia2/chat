# Aprende a hora em que cada cliente costuma escrever (#3101, decisão D4): conta qualquer mensagem que ele escreveu nos
# últimos 180 dias, por hora, no fuso dele (o mesmo resolvedor do Porteiro). Com pelo menos MINIMO mensagens, a hora é a
# de mais mensagens somando a hora vizinha de cada lado (alisa o ruído); abaixo disso, nula.
#
# Roda todo dia (Autonomia::MelhorHorario::AprenderJob) só para quem escreveu nas últimas 24 h: quem não escreveu não
# mudou. Em lotes, com uma consulta por fuso.
class Autonomia::MelhorHorario::Aprender
  PERIODO = 180.days
  MINIMO = 3
  LOTE = 500
  HORAS = 24

  def self.rodar(agora: Time.current)
    ids = mensagens.where(created_at: (agora - 1.day)..agora).distinct.pluck(:sender_id)
    ids.each_slice(LOTE) { |lote| new(lote, agora).gravar }
  end

  # O que o cliente escreveu. Sem a ordem padrão da mensagem, que barra o DISTINCT e o GROUP BY.
  def self.mensagens
    Message.incoming.where(sender_type: 'Contact').reorder(nil)
  end

  # A hora com mais mensagens, contando as duas vizinhas; no empate, a de mais mensagens sozinha, depois a mais cedo.
  def self.hora_de(por_hora)
    return nil if por_hora.sum < MINIMO

    (0...HORAS).max_by do |vez|
      [por_hora[(vez - 1) % HORAS] + por_hora[vez] + por_hora[(vez + 1) % HORAS], por_hora[vez], -vez]
    end
  end

  def initialize(contact_ids, agora)
    @contatos = Contact.where(id: contact_ids).includes(:account).to_a
    @agora = agora
  end

  def gravar
    linhas = @contatos.group_by { |contato| fuso(contato) }.flat_map { |fuso, contatos| linhas_do_fuso(fuso, contatos) }
    Autonomia::HorarioDeResposta.upsert_all(linhas, unique_by: %i[account_id contact_id]) if linhas.any? # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def linhas_do_fuso(fuso, contatos)
    contagens = contagens_por_hora(fuso, contatos.map(&:id))
    contatos.map do |contato|
      por_hora = Array.new(HORAS) { |vez| contagens[[contato.id, vez]].to_i }
      { account_id: contato.account_id, contact_id: contato.id, por_hora: por_hora, respostas: por_hora.sum,
        hora: self.class.hora_de(por_hora), calculado_em: @agora }
    end
  end

  # { [contact_id, hora] => mensagens }, a hora no fuso dado.
  def contagens_por_hora(fuso, ids)
    hora_local = Message.sanitize_sql_array(["EXTRACT(HOUR FROM (messages.created_at AT TIME ZONE 'UTC') AT TIME ZONE ?)::int", fuso])
    self.class.mensagens.where(sender_id: ids, created_at: (@agora - PERIODO)..@agora).group(:sender_id, Arel.sql(hora_local)).count
  end

  # O nome IANA, que o Postgres entende (o Resolver pode devolver o nome do Rails, como "Brasilia").
  def fuso(contato)
    nome = Crm::Timezone::Resolver.new(contact: contato, account: contato.account).name_or_default
    ActiveSupport::TimeZone[nome].tzinfo.name
  end
end
