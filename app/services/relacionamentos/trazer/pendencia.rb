# O que falta resolver numa linha com problema de "Trazer minha lista" (#2896), em palavras da tela:
# - `tipo`: o campo que a pessoa conserta (`telefone`, `email`, `nome`, `sem_contato`, `duplicada`) ou `formula`, quando
#   o erro está num campo que a tela não conserta;
# - `motivo`: o código do que deu errado, os mesmos da recusa de um conserto (ContactImports::Trazer::Conserto). A linha
#   repetida não tem;
# - `campo`: só no tipo `formula`, o campo em que a fórmula está (hoje, a empresa).
#
# Entra com os motivos que a leitura gravou na linha (ou o que sobrou do último conserto) e com as células dela como
# estão agora, já com o que a pessoa consertou por cima. A fórmula num campo sem conserto vem antes de tudo: consertar
# o resto não faria a linha entrar, então ela aparece direto como `formula` e só pode ficar de fora.
class Relacionamentos::Trazer::Pendencia
  Resultado = Struct.new(:tipo, :motivo, :campo, keyword_init: true)
  # O motivo da linha repetida => a célula em que ela repete a outra.
  REPETIDA = { 'duplicate_phone_in_file' => 'phone', 'duplicate_email_in_file' => 'email' }.freeze
  # O tipo de cada motivo, na ordem em que valem: o primeiro que a linha tiver decide.
  TIPO_DOS_MOTIVOS = {
    'duplicada' => REPETIDA.keys, 'sem_contato' => %w[missing_contact],
    'telefone' => %w[blank_phone_number formula_phone_number invalid_brazilian_mobile_number], 'email' => %w[blank_email invalid_email]
  }.freeze
  FORMULA = 'formula_detected'.freeze
  SEM_NOME = 'blank_name'.freeze
  NOME = 'nome'.freeze
  TIPO_SEM_CONSERTO = 'formula'.freeze
  # A célula com fórmula que a tela conserta => o tipo da linha.
  CONSERTAVEIS = { 'phone' => 'telefone', 'email' => 'email', 'name' => NOME }.freeze
  # A célula com fórmula que a tela não conserta => o campo que a tela diz.
  SEM_CONSERTO = { 'company' => 'empresa' }.freeze

  # motivos: ['formula_detected', 'invalid_email']; celulas: { 'name' =>, 'phone' =>, 'email' =>, 'company' => };
  # com_nome: a planilha tem coluna de nome (sem ela, a linha sem nome não é problema).
  def initialize(motivos, celulas, com_nome:)
    @motivos = motivos
    @celulas = celulas
    @com_nome = com_nome
  end

  # Sem nada que se reconheça, a linha fica como problema de nome, sem motivo.
  def call
    da_formula_sem_conserto || dos_motivos_da_leitura || da_formula_que_se_conserta || do_nome || Resultado.new(tipo: NOME)
  end

  private

  def dos_motivos_da_leitura
    TIPO_DOS_MOTIVOS.each do |tipo, codigos|
      motivo = @motivos.find { |codigo| codigos.include?(codigo) }
      return Resultado.new(tipo: tipo, motivo: (motivo unless REPETIDA.key?(motivo))) if motivo
    end
    nil
  end

  def da_formula_que_se_conserta
    alvo = CONSERTAVEIS.keys.find { |celula| formula?(celula) }
    alvo && Resultado.new(tipo: CONSERTAVEIS.fetch(alvo), motivo: FORMULA)
  end

  # A leitura só diz "sem nome" na linha sem outro erro: na linha com fórmula, o nome que falta é visto pela célula.
  def do_nome
    falta = @motivos.include?(SEM_NOME) || (@com_nome && @motivos.include?(FORMULA) && @celulas['name'].to_s.strip.empty?)
    Resultado.new(tipo: NOME, motivo: SEM_NOME) if falta
  end

  def da_formula_sem_conserto
    alvo = SEM_CONSERTO.keys.find { |celula| formula?(celula) }
    alvo && Resultado.new(tipo: TIPO_SEM_CONSERTO, motivo: FORMULA, campo: SEM_CONSERTO.fetch(alvo))
  end

  def formula?(alvo)
    CampaignImports::CsvSanitizer.formula_like?(@celulas[alvo], allow_phone_plus: alvo == 'phone')
  end
end
