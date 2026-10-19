module Crm
  module Ai
    # Critério de IA padrão de uma etapa (#1548). O texto mora no i18n do back (`crm.stage_criteria`), para o pacote de
    # textos por tipo de conta (#1545) poder trocar nome e critério juntos.
    #
    # 1. Modelo + posição: o funil nasceu de um modelo (`metadata.template`, #1498) e a etapa é a E<n> dele. Vale mesmo
    #    com o nome trocado, no idioma da pessoa.
    # 2. Nome: funis antigos, etapas avulsas e chamadas sem modelo. Os nomes do mapa são em português e a frase também.
    class DefaultStageCriteria
      I18N_SCOPE = 'crm.stage_criteria'.freeze
      NAME_LOCALE = :pt_BR
      # Os modelos de Vender; os outros são de Atender (Crm::Pipeline::TEMPLATES). RENOVACAO: corretora (#1802).
      SELL_TEMPLATES = %w[VENDAS RENOVACAO].freeze

      # Nome da etapa → chave do critério. Funil de Vender lê só este mapa. Ele já tinha nomes de etapas de Atender
      # (#1384); ficam aqui para os funis que existem não mudarem.
      NAME_KEYS = {
        # Funil comercial inicial, de antes da tela de criar funil.
        'novo' => 'legado.novo',
        'em atendimento' => 'legado.em_atendimento',
        'proposta' => 'legado.proposta',
        'fechamento' => 'legado.fechamento',
        'perdido' => 'legado.perdido',
        # #1384: etapas do modelo Vendas, em linguagem de quem atende.
        'novo contato' => 'vendas.e1',
        'em conversa' => 'vendas.e2',
        'proposta enviada' => 'vendas.e3',
        'negociação' => 'vendas.e4',
        'fechado' => 'vendas.e5',
        # #1384: etapas dos modelos Atendimento e Agendamentos ("Em atendimento" e "Novo contato" já existem acima).
        'novo pedido' => 'atendimento.e1',
        'esperando o cliente' => 'atendimento.e3',
        'resolvido' => 'atendimento.e4',
        'horário marcado' => 'agendamentos.e2',
        'atendido' => 'agendamentos.e4',
        'não veio' => 'legado.nao_veio'
      }.freeze

      # #1498: só funil de Atender — as etapas dos modelos Pós-venda, Cobrança e Agendamento, e nomes que em venda querem
      # dizer outra coisa ("Em atendimento" não fala de proposta). Funil de Vender não as recebe.
      ATENDER_NAME_KEYS = {
        'novo' => 'legado.novo_atender',
        'em atendimento' => 'atendimento.e2',
        'compra feita' => 'pos_venda.e1',
        'acompanhando' => 'pos_venda.e2',
        'tudo certo' => 'pos_venda.e4',
        'a vencer' => 'cobranca.e1',
        'atrasado' => 'cobranca.e2',
        'prometeu pagar' => 'cobranca.e3',
        'pago' => 'cobranca.e4',
        'pediu horário' => 'agendamentos.e1',
        'precisa remarcar' => 'agendamentos.e3'
      }.freeze

      def self.criteria_for(stage_name, atender: false, template: nil, position: nil)
        by_template(template, position, atender) || by_name(stage_name, atender)
      end

      def self.metadata_for(stage_name, atender: false, template: nil, position: nil)
        criteria = criteria_for(stage_name, atender: atender, template: template, position: position)
        return {} if criteria.blank?

        { 'ai_criteria' => criteria }
      end

      # O modelo precisa ser conhecido e do mesmo tipo do funil (`counts_as_sale`, que decide o tipo): Vender não recebe
      # frase de Atender, nem o contrário. Modelo de outro tipo é ignorado e a etapa cai no nome.
      def self.by_template(template, position, atender)
        template = template.to_s
        return unless ::Crm::Pipeline::TEMPLATES.include?(template)
        return if SELL_TEMPLATES.include?(template) == atender

        index = Integer(position.to_s, 10, exception: false)
        return unless index&.positive?

        key = "#{I18N_SCOPE}.#{template.downcase}.e#{index}"
        I18n.t(key) if I18n.exists?(key)
      end

      def self.by_name(stage_name, atender)
        name = stage_name.to_s.squish.downcase
        key = (atender && ATENDER_NAME_KEYS[name]) || NAME_KEYS[name]
        return if key.blank?

        I18n.t("#{I18N_SCOPE}.#{key}", locale: NAME_LOCALE)
      end

      private_class_method :by_template, :by_name
    end
  end
end
