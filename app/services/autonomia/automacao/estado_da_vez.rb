# O estado de uma campanha da vez (#2414 G55), lido do banco a cada conferência: as execuções desta vez (a automação e a
# marca do recorrente sem o alvo), quem passou pelo passo campanha (tem o registro dele), quem chegou a ele (o registro
# "aguardando"), quem fechou sem passar e quem ainda está aberto antes dele. Nada é somado: a mesma leitura dá a mesma
# resposta, repetida quantas vezes for.
#
# `rede`: na rede de segurança (CampanhaDaOcorrencia::REDE), a execução travada (aberta, sem espera, sem andar há mais de
# REDE) e o lote que não rodou depois de REDE contam como fora. A que espera segura a vez.
#
# As execuções da vez são achadas pelo começo da marca (`evento LIKE`), pelo índice idx_autonomia_automacao_execucoes_vez
# (text_pattern_ops), sem ler as das outras vezes da automação.
class Autonomia::Automacao::EstadoDaVez
  Execucao = ::Autonomia::Automacao::Execucao
  Registro = ::Autonomia::Automacao::Registro
  Ocorrencia = ::Autonomia::Automacao::CampanhaDaOcorrencia

  def initialize(vez, rede: false)
    @vez = vez
    @rede = rede
    @limite = Time.current - Ocorrencia::REDE
  end

  # A vez pode fechar: os lotes rodaram (ou, na rede, passou REDE) e ninguém aberto segura antes do passo.
  def pronta? = lotes_ok? && !seguram.exists?

  # A primeira execução que chegou ao passo (onde fica o registro da vez), ou nil.
  def primeira
    return @primeira if defined?(@primeira)

    id = Registro.where(execucao_id: execucoes.select(:id), passo: @vez.passo, motivo: Ocorrencia::AGUARDANDO).order(:id).pick(:execucao_id)
    @primeira = id && Execucao.find_by(id: id)
  end

  # Onde fica o registro da vez: a primeira que chegou; sem chegada, a primeira execução da vez; sem nenhuma, nil.
  def dona = primeira || execucoes.order(:id).first

  # Na rede, sem a contagem dos lotes (a varredura começou antes da atualização que trouxe a contagem, ou parou antes de
  # contar), o texto diz isso em vez de "lotes que não rodaram".
  def motivo_da_saida
    return 'campanha_da_vez_saiu_sem_contar_lotes' if @rede && @vez.lotes.nil?

    fora.positive? || lotes_fora.positive? ? 'campanha_da_vez_saiu_pela_rede' : 'campanha_da_vez_saiu'
  end

  def contagem
    { 'chegaram' => chegaram, 'sairam' => sairam, 'fora' => fora, 'lotes_fora' => lotes_fora, 'horas' => Ocorrencia::REDE.in_hours.to_i }
  end

  private

  def execucoes
    padrao = "#{ActiveRecord::Base.sanitize_sql_like(@vez.ocorrencia)}:%"
    Execucao.where(automacao_id: @vez.automacao_id).where('autonomia_automacao_execucoes.evento LIKE ?', padrao)
  end

  def passaram = Registro.where(execucao_id: execucoes.select(:id), passo: @vez.passo).select(:execucao_id)

  def abertas_antes = execucoes.where(finalizada_em: nil).where.not(id: passaram)

  # As travadas: abertas, sem espera e sem andar há mais de REDE.
  def travadas = abertas_antes.where.not(estado: 'esperando').where(updated_at: ...@limite)

  def seguram = @rede ? abertas_antes.where.not(id: travadas.select(:id)) : abertas_antes

  def lotes_ok? = @vez.lotes_rodaram? || (@rede && @vez.created_at <= @limite)

  def chegaram
    Registro.where(execucao_id: execucoes.select(:id), passo: @vez.passo, motivo: Ocorrencia::AGUARDANDO).distinct.count(:execucao_id)
  end

  def sairam = execucoes.where.not(finalizada_em: nil).where.not(id: passaram).count

  def fora = @rede ? travadas.count : 0

  def lotes_fora = @rede && !@vez.lotes_rodaram? ? @vez.lotes_fora : 0
end
