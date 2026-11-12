# O que o ensaio (Ensaio) confere antes de dizer que a mensagem, o aviso ou o e-mail "sairia": as perguntas do motor que
# dependem da conversa e de quem age, sem mandar nada. Cada pergunta devolve [faria, dados] quando o motor não mandaria,
# ou nil.
#
# #2604: quem age (quem ligou a automação, ou quem vai ligar: o controller escolhe) precisa enxergar a conversa
# (NaConversa#sem_acesso) e, no e-mail, poder começar conversa na caixa (PassoDeEmail, Acesso.pessoa_comeca_conversa?).
# Sem isso o motor pausa a automação (`sem_acesso`): o ensaio diz "pausaria", com quem, e o caminho acaba ali.
class Autonomia::Automacao::EnvioNoEnsaio
  PAUSARIA = 'pausaria'.freeze
  # Depois destes o motor não segue: o caminho do ensaio acaba no passo.
  ACABA = [PAUSARIA].freeze

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

  private

  def pausaria = [PAUSARIA, { motivo: 'quem_ligou_sem_acesso', quem: @quem_age.name }]
end
