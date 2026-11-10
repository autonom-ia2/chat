# O estado de uma campanha da vez (#2414 G55), lido do banco a cada conferência: as execuções desta vez (a automação e a
# marca do recorrente sem o alvo), quem passou pelo passo campanha (tem o registro dele), quem chegou a ele (o registro
# "aguardando"), quem fechou sem passar e quem ainda está aberto antes dele. Nada é somado: a mesma leitura dá a mesma
# resposta, repetida quantas vezes for.
#
# `rede`: na rede de segurança (CampanhaDaOcorrencia::REDE), a execução travada (aberta, sem espera, sem andar há mais de
# REDE) e o lote que não rodou depois de REDE contam como fora. A que espera segura a vez até ESPERA_MAXIMA depois de a
# vez abrir; daí em diante também conta como fora (a espera sem prazo renova o `due_at` e seguraria a vez para sempre).
#
# As execuções da vez são achadas pelo começo da marca (`evento LIKE`), pelo índice idx_autonomia_automacao_execucoes_vez
# (text_pattern_ops), sem ler as das outras vezes da automação. Tudo na conta da vez.
#
# Custo (B5 do lote 3): cada chegada e cada fechamento confere a vez. "Passou pelo passo" é um NOT EXISTS por execução
# (o índice do registro por execução), não a lista inteira de quem passou; e a pergunta "alguém segura?" procura uma só,
# do fim da marca para o começo (os lotes rodam em ordem, então quem ainda não chegou está no fim): com a vez cheia, acha
# na primeira linha, em vez de ler a vez inteira a cada chegada.
class Autonomia::Automacao::EstadoDaVez
  Execucao = ::Autonomia::Automacao::Execucao
  Registro = ::Autonomia::Automacao::Registro
  Ocorrencia = ::Autonomia::Automacao::CampanhaDaOcorrencia

  # Passou pelo passo quem tem o registro dele gravado pelo Executor (inclusive o pulado que segue adiante). Os registros
  # que a própria vez grava na execução dona (Ocorrencia::DA_VEZ) não contam: ela pode nem ter chegado ao passo ainda.
  NAO_PASSOU = <<~SQL.squish.freeze
    NOT EXISTS (SELECT 1 FROM autonomia_automacao_registros registro
                WHERE registro.execucao_id = autonomia_automacao_execucoes.id AND registro.account_id = :conta
                  AND registro.passo = :passo AND (registro.motivo IS NULL OR registro.motivo NOT IN (:da_vez)))
  SQL

  def initialize(vez, rede: false)
    @vez = vez
    @rede = rede
    @limite = Time.current - Ocorrencia::REDE
  end

  # A vez pode fechar: os lotes rodaram (ou, na rede, passou REDE) e ninguém aberto segura antes do passo.
  def pronta? = lotes_ok? && !alguem_segura?

  # A primeira execução que chegou ao passo (onde fica o registro da vez), ou nil.
  def primeira
    return @primeira if defined?(@primeira)

    id = registros.where(execucao_id: execucoes.select(:id), motivo: Ocorrencia::AGUARDANDO).order(:id).pick(:execucao_id)
    @primeira = id && Execucao.find_by(id: id, account_id: @vez.account_id)
  end

  # Onde fica o registro da vez: a primeira que chegou; sem chegada, a primeira execução da vez; sem nenhuma, nil.
  def dona = primeira || execucoes.order(:id).first

  # Na rede, sem a contagem dos lotes (a varredura começou antes da atualização que trouxe a contagem, ou parou antes de
  # contar), o texto diz isso em vez de "lotes que não rodaram".
  def motivo_da_saida
    return 'campanha_da_vez_saiu_sem_contar_lotes' if @rede && @vez.lotes.nil?

    fora.positive? || lotes_fora.positive? || esperaram.positive? ? 'campanha_da_vez_saiu_pela_rede' : 'campanha_da_vez_saiu'
  end

  def contagem
    { 'chegaram' => chegaram, 'sairam' => sairam, 'fora' => fora, 'lotes_fora' => lotes_fora, 'esperaram' => esperaram,
      'horas' => Ocorrencia::REDE.in_hours.to_i, 'dias' => Ocorrencia::ESPERA_MAXIMA.in_days.to_i }
  end

  private

  def execucoes
    padrao = "#{ActiveRecord::Base.sanitize_sql_like(@vez.ocorrencia)}:%"
    Execucao.where(account_id: @vez.account_id, automacao_id: @vez.automacao_id).where('autonomia_automacao_execucoes.evento LIKE ?', padrao)
  end

  def registros = Registro.where(account_id: @vez.account_id, passo: @vez.passo)

  def sem_passar(relacao) = relacao.where(NAO_PASSOU, conta: @vez.account_id, passo: @vez.passo, da_vez: Ocorrencia::DA_VEZ)

  def abertas_antes = sem_passar(execucoes.where(finalizada_em: nil))

  # Uma só que segura basta: procurada do fim da marca para o começo (veja o custo, no alto).
  def alguem_segura? = seguram.reorder(evento: :desc).limit(1).pluck(:id).any?

  # As travadas: abertas, sem espera e sem andar há mais de REDE.
  def travadas = abertas_antes.where.not(estado: 'esperando').where(updated_at: ...@limite)

  # As que esperam depois de ESPERA_MAXIMA da vez (só na rede).
  def esperas_longas = esgotada? ? abertas_antes.where(estado: 'esperando') : Execucao.none

  def esgotada? = @rede && @vez.created_at <= Time.current - Ocorrencia::ESPERA_MAXIMA

  def seguram = @rede ? abertas_antes.where.not(id: travadas.select(:id)).where.not(id: esperas_longas.select(:id)) : abertas_antes

  def lotes_ok? = @vez.lotes_rodaram? || (@rede && @vez.created_at <= @limite)

  def chegaram
    registros.where(execucao_id: execucoes.select(:id), motivo: Ocorrencia::AGUARDANDO).distinct.count(:execucao_id)
  end

  def sairam = sem_passar(execucoes.where.not(finalizada_em: nil)).count

  def fora = @rede ? travadas.count : 0

  def esperaram = esgotada? ? esperas_longas.count : 0

  def lotes_fora = @rede && !@vez.lotes_rodaram? ? @vez.lotes_fora : 0
end
