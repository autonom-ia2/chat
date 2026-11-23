# O passo "Mandar cupom" (#3100, F4 do épico #3095): acha ou sorteia o código do cupom para o contato do alvo e manda a
# mensagem com ele. É o passo "mensagem" inteiro (PassoDeMensagem: quem não recebe pula, a janela de 24 h fechada manda o
# modelo aprovado no lugar ou para, o robô do outro lado, o número novo, a conversa nova), com os dados do cupom no
# texto: `cupom.codigo`, `cupom.oferta` e `cupom.vale_ate` (Fidelidade::ValoresDoCupom), que só existem aqui.
#
# - Um código por pessoa e cupom (Fidelidade::CodigoDoCupom): mandar de novo manda o mesmo código, com a mesma validade.
# - A validade conta de quando o código chega à pessoa: o primeiro envio que sai grava `enviado_em` e `vale_ate`. O
#   código sorteado num envio que não saiu fica sem eles e não vale no Conferir.
# - Pula, com o motivo: cupom apagado (`sem_cupom`) ou pausado (`cupom_pausado`), alvo sem contato
#   (`cupom_sem_contato`), código que a pessoa já usou (`cupom_ja_usado`) ou que venceu (`cupom_vencido`).
#
# Roda pela porta dos passos novos (PassosNovos, flag `automacao_passos_novos`) e, como manda mensagem, pelo caminho dos
# passos que mandam (Executor#passo_nativo: a flag das mensagens, o ritmo de envio, a janela). Quem pode: quem cuida do
# cartão, `fidelidade_manage` (o mesmo de criar e mandar cupom na tela). Quem salva precisa dela; quem ligou também,
# conferido a cada execução: sem ela, a automação pausa.
class Autonomia::Automacao::PassoDeMandarCupom < Autonomia::Automacao::PassoDeMensagem
  TIPO = 'mandar_cupom'.freeze
  PERMISSAO = 'fidelidade_manage'.freeze

  def self.do_tipo?(passo) = passo['tipo'] == TIPO

  def self.caminhos(passo)
    [passo['texto'], *Array(passo.dig('modelo', 'variaveis'))].flat_map { |partes| ::Autonomia::Automacao::Texto.caminhos(partes) }
  end

  # O que a régua de sempre da Receita confere (Receita::Leitura): os dados de fora do cupom.
  def self.caminhos_lidos(passo) = caminhos(passo).reject { |caminho| ::Fidelidade::ValoresDoCupom.do_cupom?(caminho) }

  # O que a Receita confere ao salvar (`conferencia`: PassosNovos::Conferencia). Sem conta (o catálogo), nada.
  def self.problemas_ao_salvar(passo, conferencia)
    conta = conferencia.conta
    return [] if conta.nil?

    id = passo['id']
    [*(texto(:passo_desligado, passo: id) unless ::Autonomia::Automacao::Motor.mensagens?(conta)),
     *(fidelidade(:sem_permissao_cupom, passo: id) if conferencia.account_user && !conferencia.account_user.permission_granted?(PERMISSAO)),
     *(fidelidade(:sem_cupom, passo: id) unless ::Fidelidade::Cupom.da_conta(conta).exists?(id: passo['cupom_id'])),
     *(fidelidade(:sem_codigo, passo: id) unless com_codigo?(passo)),
     *dados_do_cupom_desconhecidos(passo).map { |caminho| texto(:valor_desconhecido, passo: id, caminho: caminho) },
     *::Autonomia::Automacao::ModeloWhatsapp.problemas_ao_salvar(conta, id, passo['modelo'])]
  end

  def self.com_codigo?(passo) = ::Autonomia::Automacao::Texto.caminhos(passo['texto']).include?(::Fidelidade::ValoresDoCupom::CODIGO)

  def self.dados_do_cupom_desconhecidos(passo)
    caminhos(passo).select { |caminho| ::Fidelidade::ValoresDoCupom.do_cupom?(caminho) }
                   .reject { |caminho| ::Fidelidade::ValoresDoCupom::CAMINHOS.include?(caminho) }.uniq
  end

  # O que o ensaio diz, sem sortear nem mandar nada: [o que faria, dados].
  def self.ensaiar(passo, contato, conta)
    cupom = ::Fidelidade::Cupom.da_conta(conta).find_by(id: passo['cupom_id'])
    return ['sem_cupom', {}] unless cupom
    return ['cupom_pausado', {}] unless cupom.ligado
    return ['cupom_sem_contato', {}] if contato.nil?

    codigo = ::Fidelidade::CupomCodigo.find_by(cupom_id: cupom.id, contact_id: contato.id)
    motivo = codigo && motivo_do_codigo(codigo)
    return [motivo, {}] if motivo

    [TIPO, { cupom: cupom.nome, mesmo_codigo: codigo&.enviado_em.present? }]
  end

  def self.motivo_do_codigo(codigo)
    return 'cupom_ja_usado' if codigo.usado_em
    return 'cupom_vencido' if codigo.vale_ate && codigo.vale_ate < Time.current

    nil
  end

  def self.texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  def self.fidelidade(chave, **valores) = texto("fidelidade.#{chave}", **valores)

  def executar
    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_permissao_fidelidade', dados: {}) unless pode?

    pulo = preparar
    return pulo if pulo

    resultado = super
    return resultado unless resultado.tipo == :ok

    @codigo.update!(enviado_em: @codigo.enviado_em || Time.current, vale_ate: @vale_ate, automacao_execucao_id: @execucao.id)
    Resultado.new(tipo: :ok, motivo: resultado.motivo, dados: resultado.dados.merge('cupom_id' => @codigo.cupom_id))
  end

  private

  # Acha o cupom e o código da pessoa (sorteia, se ela ainda não tem) e a validade que ele terá ao chegar. Devolve o pulo,
  # ou nil para mandar.
  def preparar
    cupom = ::Fidelidade::Cupom.da_conta(@execucao.account).find_by(id: @passo['cupom_id'])
    return pulado('sem_cupom') unless cupom
    return pulado('cupom_pausado') unless cupom.ligado

    contato = ::Autonomia::Automacao::Contexto.de(@alvo, execucao: @execucao).contato
    return pulado('cupom_sem_contato') if contato.nil?

    codigo = ::Fidelidade::CodigoDoCupom.new(cupom).para(contato)
    motivo = self.class.motivo_do_codigo(codigo)
    return pulado(motivo) if motivo

    @codigo = codigo
    @vale_ate = codigo.vale_ate || (Time.current + cupom.validade_dias.days)
    nil
  end

  # Quem ligou ainda cuida do cartão? Na execução de um bloco, quem ligou a automação de cima (Execucao#dona).
  def pode?
    quem = @execucao.dona.ligada_por
    account_user = quem && @execucao.account.account_users.find_by(user_id: quem.id)
    account_user&.permission_granted?(PERMISSAO) || false
  end

  # Os valores da execução, com os do cupom por cima (só depois de achar o código).
  def valores
    base = super
    return base unless @codigo

    @valores_do_cupom ||= ::Fidelidade::ValoresDoCupom.new(base, codigo: @codigo, vale_ate: @vale_ate)
  end
end
