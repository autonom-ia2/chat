# Os passos que esperam resposta (PassosQueEsperam) no ensaio (#2498): o que fariam nesta conversa, pelas mesmas
# perguntas do motor, sem fazer nada. Nada é mandado, nenhum pedido chega a ninguém, nenhuma reunião é marcada e a IA
# não é chamada.
#
# - Aprovação: a quem o pedido iria agora (as pessoas que alcançam o registro), ou que ninguém pode aprovar e o caminho
#   "Se ninguém responder a tempo" rodaria na hora.
# - Reunião: a pessoa, a página dela e os 3 horários livres que ofereceria agora, como o cliente leria; só depois o canal
#   como a mensagem (a janela de 24 h fechada sem modelo para a execução). Sem com quem marcar ou sem a página dela,
#   seguiria sem reunião pelo caminho "Se o cliente não responder", com o mesmo motivo do motor.
# - Pesquisa: a pesquisa recente que pularia; só depois o canal como a mensagem.
# A ordem é a do motor (PassoDeReuniao, PassoDePesquisa): o que ele confere antes de mandar, o ensaio confere antes do
# canal. Sem horário e com a janela fechada, por exemplo, os dois seguem por "Se pedir outro horário".
# Cada um abre os caminhos dele, sem escolher (como o "decidir"): a reunião marcada segue para o resto da receita.
# No card sem conversa (#2631, #2680), como o motor: a aprovação vai a quem alcança o card; a reunião e a pesquisa pulam
# com `sem_conversa` e seguem para o passo seguinte.
class Autonomia::Automacao::EsperaNoEnsaio
  Esperam = ::Autonomia::Automacao::PassosQueEsperam
  Reuniao = ::Autonomia::Automacao::PassoDeReuniao
  MARCOU = 'marcou'.freeze

  # `alvo`: o registro do ensaio (a conversa, o card ou o contato); `conversa`: a conversa em que os passos agem agora.
  def initialize(conta:, alvo:, conversa:, envio:, roteiro:)
    @conta = conta
    @alvo = alvo
    @conversa = conversa
    @envio = envio
    @roteiro = roteiro
  end

  # [o nó do ensaio, o próximo passo neste caminho (nil quando abriu caminhos ou acabou)]. O bloco ensaia um caminho a
  # partir do primeiro passo dele.
  def ensaiar(passo, valores, &caminho)
    @caminho = caminho
    desligado = Esperam.desligado(passo, @conta)
    return [no(passo, desligado), nil] if desligado

    case passo['tipo']
    when Esperam::APROVACAO then aprovacao(passo)
    when Esperam::REUNIAO then reuniao(passo, valores)
    else pesquisa(passo, valores)
    end
  end

  private

  def aprovacao(passo)
    para = ::Autonomia::Automacao::PassoDeAprovacao.para(@conta, passo, @alvo)
    return [no(passo, 'sem_quem_aprove', {}, [ramo(passo, Esperam.sem_resposta(passo))]), nil] if para.empty?

    [no(passo, passo['tipo'], { para: para.map(&:name) }, ramos(passo)), nil]
  end

  def reuniao(passo, valores)
    return sem_conversa(passo) if @conversa.nil?

    pessoa = responsavel(passo)
    return sem_reuniao(passo, Reuniao::SEM_RESPONSAVEL) unless pessoa

    agenda = ::Autonomia::Automacao::AgendaDaReuniao.new(@conta, pessoa, passo['duracao'])
    return sem_reuniao(passo, Reuniao::SEM_PAGINA, { por: agenda.por }) unless agenda.pagina

    horarios = agenda.horarios.map { |inicio| agenda.rotulo(inicio) }
    return [no(passo, 'sem_horario', {}, [ramo(passo, 'outro_horario')]), nil] if horarios.empty?

    do_canal(passo, valores) || oferta(passo, pessoa, horarios)
  end

  # Como o motor (PassoDeReuniao#sem_reuniao): seguiria sem reunião, pelo caminho "Se o cliente não responder".
  def sem_reuniao(passo, motivo, dados = {}) = [no(passo, motivo, dados, [ramo(passo, Reuniao::NAO_RESPONDEU)]), nil]

  def oferta(passo, pessoa, horarios)
    dados = { quem: pessoa.name, horarios: horarios, convite: passo['convite'], **de_mensagem(passo, horarios.size) }
    [no(passo, passo['tipo'], dados, ramos_da_reuniao(passo)), nil]
  end

  # A pessoa com quem a reunião seria marcada, pela mesma escolha do motor (QuemDoPasso).
  def responsavel(passo) = ::Autonomia::Automacao::QuemDoPasso.pessoas(@conta, passo['com'], ::Autonomia::Automacao::Contexto.de(@alvo)).first

  def pesquisa(passo, valores)
    return sem_conversa(passo) if @conversa.nil?
    return seguir(passo, no(passo, 'pesquisa_recente')) if ::Autonomia::Automacao::PassoDePesquisa.recente?(@conversa.contact, passo)

    do_canal(passo, valores) || pergunta(passo)
  end

  def pergunta(passo)
    dados = { pergunta: passo['pergunta'], espera: passo['espera'], **de_mensagem(passo, ::Autonomia::Automacao::PassoDePesquisa::NOTAS.size) }
    [no(passo, passo['tipo'], dados, ramos(passo)), nil]
  end

  # O que a mensagem diz da conversa: botões ou números, e o modelo que sai com a janela fechada.
  def de_mensagem(passo, quantas)
    { botoes: ::Autonomia::Automacao::MensagemComOpcoes.botoes?(@conversa, quantas), modelo: passo.dig('modelo', 'nome') }.compact
  end

  # O canal, como a mensagem (EnvioNoEnsaio#do_canal): quem não recebe pula e segue; a janela fechada sem modelo para.
  # Com o modelo no lugar (MODELO), o passo pergunta assim mesmo, como o motor: o modelo sai e a pergunta de verdade vai
  # quando o cliente responder (o `modelo` já vem em de_mensagem).
  def do_canal(passo, valores)
    faria, dados = @envio.do_canal(passo, valores)
    return if faria.nil? || faria == ::Autonomia::Automacao::EnvioNoEnsaio::MODELO

    seguir(passo, no(passo, faria, dados.to_h))
  end

  # Como o motor (PassoDeReuniao, PassoDePesquisa): sem conversa, pula e segue.
  def sem_conversa(passo) = seguir(passo, no(passo, 'sem_conversa'))

  def seguir(passo, feito)
    acaba = ::Autonomia::Automacao::EnvioNoEnsaio::ACABA.include?(feito[:faria])
    [feito, (@roteiro.seguinte(passo['id']) unless acaba)]
  end

  def ramos(passo) = Esperam::RAMOS.fetch(passo['tipo']).map { |chave| ramo(passo, chave) }

  # A reunião marcada não abre galho: segue para o resto da receita.
  def ramos_da_reuniao(passo)
    [{ chave: MARCOU, fixo: true, passos: @caminho.call(@roteiro.seguinte(passo['id'])) }, *ramos(passo)]
  end

  def ramo(passo, chave) = { chave: chave, fixo: true, passos: @caminho.call(@roteiro.entrar(passo, chave)) }

  def no(passo, faria, dados = {}, ramos = nil)
    { id: passo['id'], tipo: passo['tipo'], faria: faria, dados: dados, ramos: ramos }.compact
  end
end
