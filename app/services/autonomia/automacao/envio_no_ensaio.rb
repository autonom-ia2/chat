# O que o ensaio (Ensaio) confere antes de dizer que a mensagem, o aviso ou o e-mail "sairia": as perguntas do motor que
# dependem da conversa e de quem age, sem mandar nada. Cada pergunta devolve [faria, dados] quando o motor não mandaria,
# ou nil.
#
# #2604: quem age (quem ligou a automação, ou quem vai ligar: o controller escolhe) precisa poder agir na conversa, a
# pergunta do Executor no começo de cada rodada e antes de cada passo que age (impedida?, Acesso#motivo_no) e dos passos
# de IA (ComIa#impedido); no e-mail, também começar conversa na caixa (PassoDeEmail, Acesso.pessoa_comeca_conversa?).
# Sem isso o motor pausa a automação: o ensaio diz "pausaria", com quem e o motivo, e o caminho acaba ali.
#
# #2609: o canal da mensagem (PassoDeMensagem#motivo_do_canal, a mesma pergunta). Contato que não recebe e tweet pulam,
# como no motor. A janela fechada (24 h, ou o limite de horas da caixa API) sem modelo que saia no lugar para a execução
# (#2573, JanelaFechada): o ensaio diz "pararia", com o motivo, e o caminho acaba ali.
class Autonomia::Automacao::EnvioNoEnsaio
  PAUSARIA = 'pausaria'.freeze
  SEM_ACESSO = 'quem_ligou_sem_acesso'.freeze
  PARARIA = 'pararia'.freeze
  # A janela está fechada e o modelo da receita sairia no lugar do texto.
  MODELO = 'modelo_no_lugar'.freeze
  # Depois destes o motor não segue: o caminho do ensaio acaba no passo.
  ACABA = [PAUSARIA, PARARIA].freeze
  JANELA = ::Autonomia::Automacao::PassoDeMensagem::MOTIVOS_DE_JANELA

  # O caminho do ensaio acaba no passo (ACABA). A mensagem automática desligada também: o motor encerra a execução na
  # mensagem, no aviso, no e-mail (Executor#passo_nativo) e no passo de IA que fala com gente (IaNoExecutor#passo_de_ia).
  # No retorno, só pula (PassoDeRetorno#executar), e o caminho segue.
  def self.acaba?(passo, faria) = ACABA.include?(faria) || (faria == 'mensagens_desligadas' && passo['tipo'] != 'retorno')

  # F4b (#2468): o nome do modelo, para a tela dizer o que sai se a janela de 24 h estiver fechada; o de propaganda
  # (lote 5, #2681) leva o aviso de custo.
  def self.modelo(passo, caixa)
    propaganda = true if ::Autonomia::Automacao::ModeloWhatsapp.propaganda?(caixa, passo['modelo'])
    { modelo: passo.dig('modelo', 'nome'), propaganda: propaganda }
  end

  # O `canal` de do_canal, menos o MODELO: o modelo sai no lugar do texto, que nem é lido (PassoDeMensagem#mandar_aqui).
  # Com o texto, nil: o passo segue como estava (o balão e o nome do modelo); com o texto vazio, [faria, dados] só com o
  # modelo.
  def self.com_o_modelo(canal, passo, pronto, caixa)
    return canal unless canal&.first == MODELO

    [passo['tipo'], modelo(passo, caixa).compact] if pronto[:faria] == 'texto_vazio'
  end

  # `acesso`: o de quem ligou, quando quem age é ele; sem ele (quem vai ligar), só o alcance da conversa conta.
  def initialize(conversa, quem_age, acesso = nil)
    @conversa = conversa
    @quem_age = quem_age
    @acesso = acesso
  end

  # Com o Acesso de quem ligou, a pergunta inteira do motor sobre o alvo (quem ligou na conta, com a permissão, e o
  # alcance; no card, o card e a conversa dele, #2631). Quem vai ligar passa pela permissão ao ligar, e o card já veio do
  # alcance de quem pede (CardsDoEnsaio): aqui, só o alcance da conversa, a mesma pergunta do Acesso#alcanca?.
  def pausaria_ao_agir(alvo)
    motivo = @acesso ? @acesso.motivo_no(alvo, nil) : motivo_do_alcance
    pausaria(motivo) if motivo
  end

  # O e-mail (G2) com o assunto, o texto e a caixa por onde sairia, ou o motivo de não sair. Não abre conversa nem manda.
  # Na ordem do motor (Executor#passo_nativo, PassoDeEmail#executar): a flag das mensagens, a caixa, quem age começa
  # conversa nela (#2604), o contato do alvo e, só então, o assunto e o texto.
  def email(passo, valores, conta:, contato:)
    return ['mensagens_desligadas'] unless ::Autonomia::Automacao::Motor.mensagens?(conta)

    caixa = ::Autonomia::Automacao::PassoDeEmail.caixa(conta, passo['caixa_id'])
    return ['caixa_de_email_indisponivel'] if caixa.nil?

    do_email(caixa, contato) || email_pronto(passo, valores, caixa)
  end

  # O e-mail, na ordem do passo: quem age começa conversa na caixa, e o e-mail sai para o contato do alvo.
  def do_email(caixa, contato)
    pausa = abre_conversa(caixa)
    return pausa if pausa

    motivo = ::Autonomia::Automacao::PassoDeEmail.motivo_do_contato(caixa.account, contato)
    [motivo, {}] if motivo
  end

  # Abrir conversa na caixa (o e-mail, a conversa nova do card sem conversa, #2680): quem age precisa começar conversa
  # nela, como PassoDeMensagem#abrir_e_mandar e PassoDeEmail.
  def abre_conversa(caixa) = (pausaria unless ::Autonomia::Automacao::Acesso.pessoa_comeca_conversa?(@quem_age, caixa))

  # A mensagem, na ordem do PassoDeMensagem#mandar: no número novo (G43), quem age começa conversa na caixa, e o número
  # novo já de outro contato pula (PassoDeMensagem#no_numero_novo); depois o canal. O "escrever" ao cliente pergunta sem
  # o modelo (`modelo: nil`): ele para na janela fechada antes de pagar a IA. Com a janela fechada e o modelo que sai no
  # lugar, devolve MODELO: quem chama sabe que o texto nem é lido (PassoDeMensagem#mandar_aqui).
  def do_canal(passo, valores, modelo: passo['modelo'])
    numero = do_numero_novo
    return numero if numero

    motivo = ::Autonomia::Automacao::PassoDeMensagem.new(execucao: nil, passo: passo, alvo: @conversa).motivo_do_canal
    return modelo_no_lugar(modelo, valores) if motivo == 'fora_da_janela' && modelo
    return pararia(motivo) if JANELA.include?(motivo)

    [motivo, {}] if motivo
  end

  private

  # G43: o contato trocou de número. Quem age começa conversa na caixa (senão pausaria), e o número novo já de outro
  # contato pula, como PassoDeMensagem#no_numero_novo. Sem troca, nil.
  def do_numero_novo
    return unless ::Autonomia::Automacao::NumeroNovo.trocou?(@conversa)
    return pausaria unless ::Autonomia::Automacao::Acesso.pessoa_comeca_conversa?(@quem_age, @conversa.inbox)

    ['numero_de_outro_contato', {}] if ::Autonomia::Automacao::NumeroNovo.de_outro_contato?(@conversa)
  end

  # Como PassoDeEmail#mandar: o valor vazio no assunto ou no texto pula com o motivo dele; depois, o em branco.
  def email_pronto(passo, valores, caixa)
    assunto = ::Autonomia::Automacao::Texto.new(passo['assunto'], valores).montar
    texto = (::Autonomia::Automacao::Texto.new(passo['texto'], valores).montar unless assunto.nil?)
    return ::Autonomia::Automacao::AgendaDaPagina.do_vazio(valores.falta_da_agenda) if texto.nil?
    return ['texto_vazio'] if texto.strip.empty? || assunto.strip.empty?

    ['email', { texto: texto, assunto: assunto.squish, caixa: caixa.name }]
  end

  def motivo_do_alcance = (SEM_ACESSO unless @conversa.nil? || ::Autonomia::Automacao::Acesso.alcanca?(@quem_age, @conversa))

  def pausaria(motivo = SEM_ACESSO) = [PAUSARIA, { motivo: motivo, quem: @quem_age.name }]

  def pararia(motivo) = [PARARIA, { motivo: motivo }]

  # Janela fechada com modelo na receita: sai o modelo ([MODELO]), ou para com o motivo de ele não sair, como
  # PassoDeMensagem#mandar_modelo e #modelo_nao_sai. O preparar só lê a lista de modelos da caixa.
  def modelo_no_lugar(modelo, valores)
    return pararia('fora_da_janela') unless ::Autonomia::Automacao::ModeloWhatsapp.aplica?(@conversa)

    pronto = ::Autonomia::Automacao::ModeloWhatsapp.new(modelo, @conversa, valores).preparar
    return [MODELO] unless pronto.is_a?(String)

    por = valores.falta_da_agenda if pronto == 'modelo_faltou_valor'
    pararia(por ? ::Autonomia::Automacao::LinkDaAgenda.motivo(por) : pronto)
  end
end
