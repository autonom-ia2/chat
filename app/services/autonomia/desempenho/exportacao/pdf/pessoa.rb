# Página 08 do PDF (#2226): passagem para uma pessoa e quem procura. Em cima, as 4 mini-estatísticas da passagem;
# à esquerda, sobre o que era e como terminou, quantas chegaram fora do horário e exemplos; à direita, quem procura
# (com quanto fecha) e a concentração.
module Autonomia::Desempenho::Exportacao::Pdf::Pessoa
  def pagina_pessoa(_pagina)
    cima = abrir_pagina(t('pessoa.titulo'), t('pessoa.subtitulo'))
    pessoa = @painel['pessoa'].to_h
    cima = minis(0, cima, largura, minis_da_pessoa(pessoa)) - 12
    metade = (largura - 24) / 2.0
    lado_da_pessoa(pessoa, 0, cima, metade)
    lado_de_quem(metade + 24, cima, metade)
  end

  private

  def minis_da_pessoa(pessoa)
    [[numero(pessoa['precisavam']), t('pessoa.precisavam')],
     [numero(pessoa['tiveram']), t('pessoa.tiveram')],
     [t('pessoa.sem_valor', n: numero(pessoa['sem_pessoa']), pct: pct(pessoa['sem_pessoa_pct'])), t('pessoa.ficaram_sem'),
      serie('alerta', :texto)],
     [t('pessoa.n_de_m', n: numero(pessoa['prometida_sem_resposta']), m: numero(pessoa['prometida'])), t('pessoa.prometeu')]]
  end

  def lado_da_pessoa(pessoa, esq, cima, largura_total)
    cima = titulo_do_bloco(t('pessoa.sobre_o_que'), esq, cima, largura_total)
    cima = ranking(itens_com_parte(pessoa['por_pedido']), esq, cima, largura_total, serie: 'alerta', limite: 5) - 8
    cima = titulo_do_bloco(t('pessoa.como_terminou'), esq, cima, largura_total)
    cima = ranking(itens_com_parte(pessoa['por_resultado']), esq, cima, largura_total, serie: 'neutro', limite: 4) - 6
    escrever(t('pessoa.fora_do_horario', n: numero(pessoa['sem_pessoa_fora_do_horario'])), esq, cima, largura_total, tamanho: 8)
    fim = exemplos(pessoa['exemplos'], esq, cima - 14, largura_total, limite: 2)
    # Quem escreve pela conta da IA conta como ela: explica "teve pessoa" com 0 mensagens da equipe.
    ressalva(t('pessoa.conta_do_agente', nome: nome_do_agente), esq, fim - 2, largura_total, tamanho: 7)
  end

  def itens_com_parte(lista)
    total = Array(lista).sum { |item| item['n'].to_i }
    Array(lista).map { |item| { nome: item['nome'], valor: item['n'], pct: parte(item['n'], total) } }
  end

  # "Conversa #N · dd/mm hh:mm" e o resumo em até 2 linhas.
  def exemplos(provas, esq, cima, largura_total, limite: 3)
    Array(provas).first(limite).reduce(cima) do |topo, prova|
      escrever(prova_curta(prova), esq, topo, largura_total, tamanho: 7.5, estilo: :semibold, tinta: serie('volume', :texto))
      escrever(reticencias(prova['resumo'], largura_total, 7), esq, topo - 10, largura_total, tamanho: 7, tinta: :apoio, altura: 18)
      topo - 30
    end
  end

  def lado_de_quem(esq, cima, largura_total)
    quem = @painel['quem'].to_h
    cima = titulo_do_bloco(t('pessoa.quem_titulo'), esq, cima, largura_total, descricao: t('pessoa.quem_descricao'))
    itens = Array(quem['ranking']).map do |linha|
      { nome: linha['nome'], valor: linha['procuras'], pct: linha['pct'],
        extra: frase_de_fechou('pessoa.fecham', linha['fecharam'], linha['compra'], linha['taxa_pct']) }
    end
    cima = ranking(itens, esq, cima, largura_total, serie: 'volume', limite: 6) - 10
    cima = titulo_do_bloco(t('pessoa.concentracao'), esq, cima, largura_total)
    minis(esq, cima, largura_total, minis_da_concentracao(quem['concentracao'].to_h), colunas: 2)
  end

  def minis_da_concentracao(concentracao)
    [[numero(concentracao['conversas_com_compra']), t('pessoa.com_compra', compra: nomes['compra'].to_s.downcase)],
     [numero(concentracao['conversas_com_fechamento']), t('pessoa.com_fechamento')],
     [numero(concentracao['conversas_uma_procura']), t('pessoa.uma_vez')],
     [pct(concentracao['top10_pct_da_compra']), t('pessoa.top10')]]
  end
end
