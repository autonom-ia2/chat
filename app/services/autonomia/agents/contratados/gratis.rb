# O PERÍODO GRÁTIS E A PAUSA DO AGENTE CONTRATADO (#3270). Cada modelo do catálogo diz os dias grátis e o preço
# (`Contratados::MODELOS`). Os dias contam da PRIMEIRA contratação do modelo na conta, uma vez por conta: contratar de
# novo, apagar e recriar não reinicia.
#
# O começo é DERIVADO, não gravado: o `created_at` do agente contratado mais antigo daquele modelo na conta, contando os
# apagados. Dá para confiar porque o agente só sai do banco pelo apagar lógico (`Agents::SoftDelete`, que deixa a linha
# com `deleted_at`); nenhum caminho do painel ou da API apaga a linha de verdade, e a marca do modelo não muda depois de
# gravada (`Agents::Contratado`). Assim não há data a mais para gravar, migrar ou corrigir à mão.
#
# Conta liberada pelo super admin (`Contratados::Liberacao`) nunca pausa e não tem contagem. Sem a liberação, passados
# os dias grátis, o agente fica PAUSADO: não responde aos clientes (`Operate.authorized_agent_inbox`), nada é apagado nem
# desligado no banco, e a Atribuição não muda. A liberação ligada, ele volta no turno seguinte.
module Autonomia::Agents::Contratados::Gratis
  GRATIS = 'gratis'.freeze
  PAUSADO = 'pausado'.freeze
  LIBERADO = 'liberado'.freeze

  # `situacao`: GRATIS, PAUSADO ou LIBERADO. `dias_restantes`: só no GRATIS. Enquanto a conta não contratou, os dias
  # inteiros do modelo. Depois, os dias do calendário que faltam até o último dia grátis, no fuso da conta.
  #
  # O último dia grátis é o dia do calendário `dias_gratis` depois do dia da primeira contratação, no fuso da conta, e
  # vale INTEIRO: contratou no dia D, a qualquer hora, o grátis vai até 23:59:59 do dia D+7 e a pausa começa à
  # meia-noite do dia seguinte. A pausa e a contagem saem da mesma data: 7 no dia em que contratou, 1 na véspera e 0 o
  # dia inteiro do último dia ("Hoje é o último dia grátis" é verdade até a meia-noite).
  Estado = Data.define(:situacao, :dias_restantes) do
    def pausado?
      situacao == PAUSADO
    end
  end

  module_function

  # -> o Estado do modelo `chave` na conta, em `agora`.
  def estado(account, chave, agora: Time.current)
    return Estado.new(situacao: LIBERADO, dias_restantes: nil) if Autonomia::Agents::Contratados::Liberacao.liberado?(account, chave)

    dias = Autonomia::Agents::Contratados::MODELOS.fetch(chave).fetch(:dias_gratis)
    comeco = inicio(account, chave)
    return Estado.new(situacao: GRATIS, dias_restantes: dias) if comeco.nil?

    fuso = fuso_da_conta(account)
    ultimo_dia = comeco.in_time_zone(fuso).to_date + dias
    hoje = agora.in_time_zone(fuso).to_date
    return Estado.new(situacao: PAUSADO, dias_restantes: nil) if hoje > ultimo_dia

    Estado.new(situacao: GRATIS, dias_restantes: (ultimo_dia - hoje).to_i)
  end

  # O fuso da conta, com o mesmo leitor do CRM (sem fuso na conta: o padrão, America/Sao_Paulo).
  def fuso_da_conta(account)
    Crm::Timezone::Resolver.new(account: account).zone_or_default
  end

  # -> quando os dias grátis começaram (o primeiro contratado do modelo na conta, apagados inclusive), ou nil.
  def inicio(account, chave)
    Autonomia::Agents::Agent.where(account_id: account.id)
                            .where("config->'#{Autonomia::Agents::Contratados::MARCA}'->>'modelo' = ?", chave)
                            .minimum(:created_at)
  end

  # O agente contratado está pausado agora? Quem não é contratado do catálogo nunca está.
  def pausado?(agent, agora: Time.current)
    chave = agent&.marca_do_contratado&.dig('modelo')
    return false if chave.nil?

    estado(agent.account, chave, agora: agora).pausado?
  end

  # O preço e o estado, como as telas leem (o catálogo e a página do agente). Valor em centavos: quem formata é a tela.
  def para_tela(account, chave)
    modelo = Autonomia::Agents::Contratados::MODELOS.fetch(chave)
    atual = estado(account, chave)
    { 'dias_gratis' => modelo.fetch(:dias_gratis), 'preco_mensal_centavos' => modelo.fetch(:preco_mensal_centavos),
      'moeda' => modelo.fetch(:moeda), 'situacao' => atual.situacao, 'dias_restantes' => atual.dias_restantes }
  end
end
