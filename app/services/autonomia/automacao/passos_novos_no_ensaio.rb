# O ensaio dos passos novos com motor (#2932–#2934), incluído no Ensaio. Como o resto do ensaio, só lê:
# - "para cada um de uma lista": quantos entrariam agora (até o teto), pela mesma régua do motor (ItensDaLista: bloqueados
#   fora, só quem quem age alcança), os primeiros nomes e quantos ficariam para a próxima vez. O galho `cada` só mostra os
#   passos, com a frase do catálogo: cada item rodaria numa execução própria. E segue, como a mãe segue.
# - "usar outra automação": entra no bloco e mostra os passos dele com os valores desta conversa, com a mesma proteção do
#   motor contra laço e fundo (Bloco::PROFUNDIDADE). Bloco que sumiu, que não é bloco ou de outro tipo de registro, diz
#   por que pularia.
# - "buscar em outro sistema": nunca busca. Diz os dados que guardaria (os nomes, nunca o endereço) e mostra os dois
#   caminhos: o de quando a busca dá certo (segue) e o galho `nao_consultou`. Na consulta pronta, diz também o que ela
#   usaria desta conversa (`entradas`). A busca de verdade só pelo botão "Buscar agora" da tela, que chama o teste do
#   passo (AutomacoesPassosNovosController#testar_consulta).
module Autonomia::Automacao::PassosNovosNoEnsaio
  private

  def passo_novo(passo, valores)
    return seguir(passo, no(passo, 'passos_novos_desligados')) unless ::Autonomia::Automacao::PassosNovos.ligados?(@conta)

    case passo['tipo']
    when 'repetir_lista' then seguir(passo, repetir_lista(passo))
    when 'usar_bloco' then seguir(passo, usar_bloco(passo, valores))
    else consultar(passo, valores)
    end
  end

  def repetir_lista(passo)
    teto = passo['teto'].to_i.clamp(1, ::Autonomia::Automacao::RepetirLista::TETO_MAXIMO)
    contagem = ::Autonomia::Automacao::ItensDaLista.new(@conta, passo['lista']).contar(acesso_do_ensaio, teto)
    cada = Array(passo[::Autonomia::Automacao::RepetirLista::RAMO]).map { |dentro| no(dentro, 'catalogo') }
    no(passo, 'repetir_lista', contagem.to_h.merge(teto: teto, ritmo: passo['ritmo']), ramos: [{ chave: 'cada', passos: cada }])
  end

  # Quem age alcança o item? Com a automação ligada, quem ligou (o Acesso do motor); sem ela, quem pede.
  def acesso_do_ensaio
    @acesso_do_ensaio ||= @acesso || ::Autonomia::Automacao::Acesso.new(::Autonomia::Automacao::Definicao.new(account: @conta, ligada_por: @usuario))
  end

  def usar_bloco(passo, valores)
    bloco = ::Autonomia::Automacao::Definicao.find_by(account_id: @conta.id, id: passo['bloco_id'], bloco: true)
    receita = bloco&.versao_ativa&.receita
    return no(passo, 'bloco_sumiu') unless receita
    return no(passo, 'bloco_de_outro_alvo') unless ::Autonomia::Automacao::Bloco.alvo(bloco) == 'Conversation'
    return no(passo, 'bloco_em_laco') if blocos_do_ensaio.include?(bloco.id)
    return no(passo, 'bloco_fundo_demais') if blocos_do_ensaio.size >= ::Autonomia::Automacao::Bloco::PROFUNDIDADE

    no(passo, 'usar_bloco', { nome: bloco.nome }, ramos: [{ chave: 'dentro', passos: dentro_do_bloco(bloco, receita, valores) }])
  end

  def blocos_do_ensaio = (@blocos_do_ensaio ||= [])

  # Os passos do bloco andam no roteiro dele; ao sair, o ensaio volta ao roteiro de quem chamou. Cada nó de dentro leva o
  # `bloco`: o id do passo é da receita do bloco, e a tela acha a frase nela.
  def dentro_do_bloco(bloco, receita, valores)
    roteiro = @roteiro
    blocos_do_ensaio.push(bloco.id)
    @roteiro = ::Autonomia::Automacao::Roteiro.new(receita, voltar: false)
    do_bloco(caminho(@roteiro.primeiro, valores), bloco.id)
  ensure
    blocos_do_ensaio.pop
    @roteiro = roteiro
  end

  def consultar(passo, valores)
    nomes = Array(passo['guardar']).pluck('nome')
    ramos = [{ chave: 'consultou', passos: caminho(@roteiro.seguinte(passo['id']), valores) },
             { chave: ::Autonomia::Automacao::PassoConsultar::RAMO,
               passos: caminho(@roteiro.entrar(passo, ::Autonomia::Automacao::PassoConsultar::RAMO), valores) }]
    [no(passo, 'consultar', { guardaria: nomes, **entradas_do_ensaio(passo, valores) }, ramos: ramos), nil]
  end

  # Na consulta pronta, o que ela usaria desta conversa (o CEP do contato), para o "Buscar agora" e para dizer quando o
  # dado está vazio. A tela mostra a quem ensaia a própria conversa; nada vai para o registro.
  def entradas_do_ensaio(passo, valores)
    return {} unless passo.dig('fonte', 'de') == ::Autonomia::Automacao::PassoConsultar::PRONTA

    { entradas: ::Autonomia::Automacao::ConsultasProntas.entradas_montadas(passo['fonte'], valores) }
  end

  # O nó que já tem `bloco` (o de um bloco dentro deste) fica com o dele.
  def do_bloco(nos, bloco_id)
    nos.map do |no|
      ramos = no[:ramos]&.map { |ramo| ramo.merge(passos: do_bloco(ramo[:passos], bloco_id)) }
      { bloco: bloco_id }.merge(no, ramos ? { ramos: ramos } : {})
    end
  end
end
