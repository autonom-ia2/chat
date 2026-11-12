# Os passos que esperam resposta (PassosQueEsperam) no ensaio (#2498): o que fariam nesta conversa, pelas mesmas
# perguntas do motor, sem fazer nada. Nada é mandado, nenhum pedido chega a ninguém, nenhuma reunião é marcada e a IA
# não é chamada.
#
# - Aprovação: a quem o pedido iria agora (as pessoas que alcançam o registro), ou que ninguém pode aprovar e o caminho
#   "Se ninguém responder a tempo" rodaria na hora.
# - Reunião: o canal como a mensagem (a janela de 24 h fechada sem modelo para a execução), a página da pessoa e os 3
#   horários livres que ofereceria agora, como o cliente leria.
# - Pesquisa: o canal como a mensagem, e a pesquisa recente que pularia.
# Cada um abre os caminhos dele, sem escolher (como o "decidir"): a reunião marcada segue para o resto da receita.
class Autonomia::Automacao::EsperaNoEnsaio
  Esperam = ::Autonomia::Automacao::PassosQueEsperam
  MARCOU = 'marcou'.freeze

  def initialize(conta:, conversa:, envio:, roteiro:)
    @conta = conta
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
    when Esperam::REUNIAO then do_canal(passo, valores) || reuniao(passo)
    else do_canal(passo, valores) || pesquisa(passo)
    end
  end

  private

  def aprovacao(passo)
    para = ::Autonomia::Automacao::PassoDeAprovacao.para(@conta, passo, @conversa)
    return [no(passo, 'sem_quem_aprove', {}, [ramo(passo, Esperam.sem_resposta(passo))]), nil] if para.empty?

    [no(passo, passo['tipo'], { para: para.map(&:name) }, ramos(passo)), nil]
  end

  def reuniao(passo)
    pessoa = responsavel(passo)
    return seguir(passo, no(passo, 'reuniao_sem_responsavel')) unless pessoa

    agenda = ::Autonomia::Automacao::AgendaDaReuniao.new(@conta, pessoa, passo['duracao'])
    return seguir(passo, no(passo, 'reuniao_sem_pagina', { por: agenda.por })) unless agenda.pagina

    horarios = agenda.horarios.map { |inicio| agenda.rotulo(inicio) }
    return [no(passo, 'sem_horario', {}, [ramo(passo, 'outro_horario')]), nil] if horarios.empty?

    dados = { quem: pessoa.name, horarios: horarios, convite: passo['convite'], **de_mensagem(passo, horarios.size) }
    [no(passo, passo['tipo'], dados, ramos_da_reuniao(passo)), nil]
  end

  # A pessoa com quem a reunião seria marcada, pela mesma escolha do motor (QuemDoPasso).
  def responsavel(passo) = ::Autonomia::Automacao::QuemDoPasso.pessoas(@conta, passo['com'], ::Autonomia::Automacao::Contexto.de(@conversa)).first

  def pesquisa(passo)
    return seguir(passo, no(passo, 'pesquisa_recente')) if ::Autonomia::Automacao::PassoDePesquisa.recente?(@conversa.contact, passo)

    dados = { pergunta: passo['pergunta'], espera: passo['espera'], **de_mensagem(passo, ::Autonomia::Automacao::PassoDePesquisa::NOTAS.size) }
    [no(passo, passo['tipo'], dados, ramos(passo)), nil]
  end

  # O que a mensagem diz da conversa: botões ou números, e o modelo que sai com a janela fechada.
  def de_mensagem(passo, quantas)
    { botoes: ::Autonomia::Automacao::MensagemComOpcoes.botoes?(@conversa, quantas), modelo: passo.dig('modelo', 'nome') }.compact
  end

  # O canal, como a mensagem (EnvioNoEnsaio#do_canal): quem não recebe pula e segue; a janela fechada sem modelo para.
  def do_canal(passo, valores)
    faria, dados = @envio.do_canal(passo, valores)
    seguir(passo, no(passo, faria, dados.to_h)) if faria
  end

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
