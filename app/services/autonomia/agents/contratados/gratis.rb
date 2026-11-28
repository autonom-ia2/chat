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
  # inteiros do modelo. Depois, os dias do calendário que faltam até o dia em que o grátis acaba, no fuso da conta: 7 no
  # dia em que contratou, 1 na véspera, 0 no último dia (o grátis acaba na hora em que contratou, 7 dias depois).
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

    fim = comeco + dias.days
    return Estado.new(situacao: PAUSADO, dias_restantes: nil) unless agora < fim

    Estado.new(situacao: GRATIS, dias_restantes: dias_do_calendario(account, agora, fim))
  end

  # Quantos dias do calendário vão de `agora` até `fim`, no fuso da conta (o mesmo leitor do CRM).
  def dias_do_calendario(account, agora, fim)
    fuso = Crm::Timezone::Resolver.new(account: account).zone_or_default
    (fim.in_time_zone(fuso).to_date - agora.in_time_zone(fuso).to_date).to_i
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
