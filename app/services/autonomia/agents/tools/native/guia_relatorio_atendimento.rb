# O Guia respondendo com os números da tela Relatórios (#3158, B8a): "quem resolveu mais conversas mês
# passado?", "qual o tempo da primeira resposta por caixa nesta semana?".
#
# Uma ferramenta própria, e não `/api/v2` no catálogo de `ler_da_conta`: o catálogo vai em toda pergunta e não
# cresce, e as rotas v2 que devolvem CSV ficam de fora. O trabalho é do `Autonomia::Guide::Relatorio`, que chama
# os mesmos builders da tela.
#
# A permissão é a da tela Relatórios (`ReportPolicy#view?`: administrador, ou função com `report_manage`),
# conferida no `call` com quem está perguntando. O Guia é de todos (#3117): quem não pode recebe a mesma frase
# de "sem acesso" que a leitura dá.
class Autonomia::Agents::Tools::Native::GuiaRelatorioAtendimento < Autonomia::Agents::Tools::Native::Base
  # A frase da leitura para um 401/403 (`Consulta#indisponivel`).
  SEM_PERMISSAO = 'O perfil de quem perguntou não tem acesso a isto: relatórios.'.freeze

  class << self
    # #2918: LÊ (os relatórios). Nas rodadas das prontas, a que escreve roda uma vez por turno.
    def escreve? = false

    def slug
      'relatorio_de_atendimento'
    end

    # #861 — o que pode ir para o registro de diagnóstico, com valor.
    def args_registraveis
      %w[tipo metrica por de ate]
    end

    def description
      'Números da tela Relatórios (conversas, resolvidas, mensagens, tempos de resposta e de resolução), no fuso ' \
        'da conta. resumo = o total do período; serie = por dia, semana ou mês; ranking = por agente, caixa, ' \
        'etiqueta ou time. Com grafico, devolve o marcador [grafico:N] para pôr na resposta. Notas de satisfação ' \
        'continuam com ler_da_conta.'
    end

    def params
      [
        { 'name' => 'tipo', 'type' => 'string', 'enum' => Autonomia::Guide::Relatorio::Pedido::TIPOS },
        { 'name' => 'metrica', 'type' => 'string', 'enum' => Autonomia::Guide::Relatorio::Pedido::METRICAS },
        { 'name' => 'por', 'type' => 'string', 'enum' => Autonomia::Guide::Relatorio::Pedido::POR.keys, 'required' => false,
          'description' => 'De quem. Sem valor, a conta inteira.' },
        { 'name' => 'id', 'type' => 'string', 'required' => false,
          'description' => 'O id lido do agente, caixa, etiqueta ou time, para resumo ou serie de um só.' },
        { 'name' => 'de', 'type' => 'string', 'description' => 'Primeiro dia, AAAA-MM-DD.' },
        { 'name' => 'ate', 'type' => 'string', 'description' => 'Último dia, incluído, AAAA-MM-DD.' },
        { 'name' => 'agrupar', 'type' => 'string', 'enum' => Autonomia::Guide::Relatorio::Pedido::AGRUPAR.keys,
          'required' => false, 'description' => 'Só na serie. Acima de 31 pontos agrupa no período seguinte.' },
        { 'name' => 'grafico', 'type' => 'boolean', 'required' => false,
          'description' => 'Só quando a pessoa pedir gráfico ou quando ele explicar melhor que o texto.' }
      ]
    end
  end

  def call
    return recusa_sem_contexto if @operador.nil?
    return SEM_PERMISSAO unless ve_relatorios?

    relatorio = ::Autonomia::Guide::Relatorio.new(account: @operador.account, contexto: @operador).call(@params)
    # O portão de confiança sabe que a resposta se apoia na conta (#593), e o id de quem aparece no relatório
    # vale como lido para o botão de tela (#590).
    @operador.lido(relatorio)
    relatorio
  rescue ::Autonomia::Guide::Relatorio::Recusado => e
    e.message
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][relatorio] account=#{@operador&.account&.id} #{e.class}: #{e.message}")
    'Não consegui ler os relatórios agora.'
  end

  private

  def ve_relatorios?
    account_user = @operador.account_user
    return false if account_user.nil?

    ReportPolicy.new({ user: @operador.user, account: @operador.account, account_user: account_user }, :report).view?
  end

  # Testar e playground não têm ninguém logado: sem saber de quem é a permissão, não há relatório.
  def recusa_sem_contexto
    'Não consigo ler os relatórios agora porque não sei quem está perguntando. Responda pelo que você já sabe.'
  end
end
