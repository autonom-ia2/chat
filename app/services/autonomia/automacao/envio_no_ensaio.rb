# O que o ensaio (Ensaio) confere antes de dizer que a mensagem, o aviso ou o e-mail "sairia": as perguntas do motor que
# dependem da conversa e de quem age, sem mandar nada. Cada pergunta devolve [faria, dados] quando o motor não mandaria,
# ou nil.
#
# #2604: quem age (quem ligou a automação, ou quem vai ligar: o controller escolhe) precisa enxergar a conversa
# (NaConversa#sem_acesso) e, no e-mail, poder começar conversa na caixa (PassoDeEmail, Acesso.pessoa_comeca_conversa?).
# Sem isso o motor pausa a automação (`sem_acesso`): o ensaio diz "pausaria", com quem, e o caminho acaba ali.
#
# #2609: o canal da mensagem (PassoDeMensagem#motivo_do_canal, a mesma pergunta). Contato que não recebe e tweet pulam,
# como no motor. A janela fechada (24 h, ou o limite de horas da caixa API) sem modelo que saia no lugar para a execução
# (#2573, JanelaFechada): o ensaio diz "pararia", com o motivo, e o caminho acaba ali.
class Autonomia::Automacao::EnvioNoEnsaio
  PAUSARIA = 'pausaria'.freeze
  PARARIA = 'pararia'.freeze
  # Depois destes o motor não segue: o caminho do ensaio acaba no passo.
  ACABA = [PAUSARIA, PARARIA].freeze
  JANELA = ::Autonomia::Automacao::PassoDeMensagem::MOTIVOS_DE_JANELA

  def initialize(conversa, quem_age)
    @conversa = conversa
    @quem_age = quem_age
  end

  def pausaria_na_conversa = (pausaria unless ::Autonomia::Automacao::Acesso.alcanca?(@quem_age, @conversa))

  # O e-mail, na ordem do passo: quem age começa conversa na caixa, e o e-mail sai para o contato desta conversa.
  def do_email(caixa)
    return pausaria unless ::Autonomia::Automacao::Acesso.pessoa_comeca_conversa?(@quem_age, caixa)

    motivo = ::Autonomia::Automacao::PassoDeEmail.motivo_do_contato(caixa.account, @conversa.contact)
    [motivo, {}] if motivo
  end

  # A mensagem, na ordem do PassoDeMensagem#mandar: no número novo (G43), quem age começa conversa na caixa; depois o
  # canal. O "escrever" ao cliente pergunta sem o modelo (`modelo: nil`): ele para na janela fechada antes de pagar a IA.
  def do_canal(passo, valores, modelo: passo['modelo'])
    novo = ::Autonomia::Automacao::NumeroNovo.trocou?(@conversa)
    return pausaria if novo && !::Autonomia::Automacao::Acesso.pessoa_comeca_conversa?(@quem_age, @conversa.inbox)

    motivo = ::Autonomia::Automacao::PassoDeMensagem.new(execucao: nil, passo: passo, alvo: @conversa).motivo_do_canal
    return modelo_no_lugar(modelo, valores) if motivo == 'fora_da_janela' && modelo
    return pararia(motivo) if JANELA.include?(motivo)

    [motivo, {}] if motivo
  end

  private

  def pausaria = [PAUSARIA, { motivo: 'quem_ligou_sem_acesso', quem: @quem_age.name }]

  def pararia(motivo) = [PARARIA, { motivo: motivo }]

  # Janela fechada com modelo na receita: sai o modelo (nil; a tela já diz qual), ou para com o motivo de ele não sair,
  # como PassoDeMensagem#mandar_modelo e #modelo_nao_sai. O preparar só lê a lista de modelos da caixa.
  def modelo_no_lugar(modelo, valores)
    return pararia('fora_da_janela') unless ::Autonomia::Automacao::ModeloWhatsapp.aplica?(@conversa)

    pronto = ::Autonomia::Automacao::ModeloWhatsapp.new(modelo, @conversa, valores).preparar
    return unless pronto.is_a?(String)

    por = valores.falta_da_agenda if pronto == 'modelo_faltou_valor'
    pararia(por ? ::Autonomia::Automacao::LinkDaAgenda.motivo(por) : pronto)
  end
end
