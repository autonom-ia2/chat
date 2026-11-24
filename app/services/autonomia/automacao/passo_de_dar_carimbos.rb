# O passo "Dar carimbos ou pontos" (#3100, F4 do épico #3095): dá carimbos (ou pontos) de presente ao contato do alvo
# (conversa, card ou contato), no cartão fidelidade da conta: aniversário, indicação, avaliação. A compra já dá carimbos
# sozinha (Fidelidade::DarPelaCompra); este passo é para o presente. O histórico da ficha mostra "Recebeu 2 carimbos:
# aniversário", com o motivo do passo.
#
# Roda pela porta dos passos novos (PassosNovos, flag `automacao_passos_novos`), como o "buscar em outro sistema".
#
# Quem pode (decisão D1 do Rodrigo, 23/11): dar carimbos fora da compra é coisa de quem cuida do cartão,
# `fidelidade_manage` (administrador no OSS). Quem salva precisa dela; quem ligou também, conferido a cada execução: sem
# ela, a automação pausa (`sem_acesso`), como nos outros passos.
#
# Ao rodar: sem cartão na conta, ou com o cartão pausado, pula com o motivo (os carimbos ficam guardados e nada novo
# entra, como na compra). O movimento é `presente`, ligado à execução (`origem`), e passa por Fidelidade::Carteira, o
# único lugar que grava saldo. Completou o cartão, dispara o gatilho "completou o cartão", depois do commit.
class Autonomia::Automacao::PassoDeDarCarimbos
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  TIPO = 'dar_carimbos'.freeze
  PERMISSAO = 'fidelidade_manage'.freeze

  # O que a Receita confere ao salvar (`conferencia`: PassosNovos::Conferencia). Sem conta (o catálogo), nada depende dela.
  def self.problemas_ao_salvar(passo, conferencia)
    return [] if conferencia.conta.nil?

    id = passo['id']
    account_user = conferencia.account_user
    [*(texto(:sem_permissao, passo: id) if account_user && !account_user.permission_granted?(PERMISSAO)),
     *(texto(:sem_cartao, passo: id) unless ::Fidelidade::Programa.da_conta(conferencia.conta))]
  end

  # O que o ensaio diz, sem gravar nada: [o que faria, dados]. Quantos a pessoa tem, com quantos ficaria e a meta.
  def self.ensaiar(passo, contato, conta)
    programa = ::Fidelidade::Programa.da_conta(conta)
    return ['sem_cartao_fidelidade', {}] unless programa
    return ['cartao_fidelidade_pausado', {}] unless programa.ligado
    return ['fidelidade_sem_contato', {}] if contato.nil?

    tem = ::Fidelidade::Saldo.find_by(programa_id: programa.id, contact_id: contato.id)&.saldo || 0
    [TIPO, { quantos: passo['quantos'].to_i, tem: tem, ficaria: tem + passo['quantos'].to_i, meta: programa.meta, unidade: programa.tipo }]
  end

  def self.texto(chave, **valores) = I18n.t("autonomia.automacao.receita.fidelidade.#{chave}", **valores)

  def initialize(execucao:, passo:, acesso:, alvo: nil, **)
    @execucao = execucao
    @passo = passo
    @acesso = acesso
    @alvo = alvo
  end

  def executar
    return sem_acesso('quem_ligou_sem_permissao_fidelidade') unless @acesso.account_user&.permission_granted?(PERMISSAO)

    programa = ::Fidelidade::Programa.da_conta(@execucao.account)
    return pulado('sem_cartao_fidelidade') unless programa
    return pulado('cartao_fidelidade_pausado') unless programa.ligado

    contato = ::Autonomia::Automacao::Contexto.de(@alvo).contato
    return pulado('fidelidade_sem_contato') if contato.nil?
    return sem_acesso('quem_ligou_sem_acesso') unless @acesso.alcanca?(contato)

    dar(programa, contato)
  end

  private

  def dar(programa, contato)
    carteira = ::Fidelidade::Carteira.new(programa, contato)
    movimento = carteira.entrar(tipo: ::Fidelidade::Movimento::PRESENTE, quantos: @passo['quantos'].to_i,
                                motivo: @passo['motivo'].to_s.strip.presence, origem: @execucao)
    ::Fidelidade::CartaoCompleto.avisar(programa.account, [[contato, movimento]]) if carteira.completou?
    Resultado.new(tipo: :ok, motivo: nil, dados: { 'contato_id' => contato.id, 'quantos' => movimento.quantos, 'saldo' => carteira.depois })
  end

  def pulado(motivo) = Resultado.new(tipo: :pulado, motivo: motivo, dados: {})

  def sem_acesso(motivo) = Resultado.new(tipo: :sem_acesso, motivo: motivo, dados: {})
end
