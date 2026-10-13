module Crm
  module Ai
    class DefaultStageCriteria
      TEMPLATES = {
        'novo' => 'Primeiro contato ou lead recém-criado. Cliente demonstrou interesse inicial, fez primeira pergunta ou respondeu pela primeira vez. Ainda não há diagnóstico de necessidade nem proposta enviada.',
        'em atendimento' => 'Conversa ativa com qualificação em andamento: agente ou IA está entendendo necessidade, coletando dados, tirando dúvidas ou agendando. Ainda não houve envio formal de proposta, orçamento ou condições comerciais.',
        'proposta' => 'Proposta, orçamento, plano ou condições comerciais já foram apresentados. Cliente está avaliando, negociando valores, prazos ou comparando opções. Ainda não confirmou fechamento nem recusa definitiva.',
        'fechamento' => 'Cliente confirmou intenção de compra, aceitou proposta, solicitou link de pagamento, assinatura ou próximo passo operacional de contratação. Conversa indica conversão iminente ou concluída.',
        'perdido' => 'Lead encerrado sem conversão: cliente recusou explicitamente, pediu para não ser contatado, informou que fechou com concorrente, número inválido ou sem resposta após tentativas definidas pelo funil, ou conversa foi encerrada pelo agente como perdida. Não usar para leads ainda em negociação ativa ou que apenas disseram "vou pensar".',
        # #1384: etapas do modelo Vendas da tela de criar funil, em linguagem de quem atende.
        'novo contato' => 'O cliente acabou de chegar: mandou a primeira mensagem ou fez a primeira pergunta. Ainda não sabemos do que ele precisa.',
        'em conversa' => 'Estamos entendendo o que o cliente precisa: tirando dúvidas, pegando dados ou marcando horário. Ainda não mandamos preço.',
        'proposta enviada' => 'O cliente já recebeu o preço, o orçamento ou a proposta e está pensando. Ainda não disse sim nem não.',
        'negociação' => 'O cliente quer fechar, mas ainda está acertando detalhes: preço, prazo, forma de pagamento ou desconto.',
        'fechado' => 'O cliente disse sim: aceitou a proposta, pagou, assinou ou pediu o próximo passo para começar.',
        # #1384: etapas dos modelos Atendimento e Agendamentos ("Em atendimento" e "Novo contato" já existem acima).
        'novo pedido' => 'O cliente acabou de pedir ajuda: contou um problema ou fez uma pergunta. Ninguém começou a resolver ainda.',
        'esperando o cliente' => 'Pedimos algo ao cliente, como uma foto, um dado ou uma resposta, e estamos esperando ele mandar.',
        'resolvido' => 'O pedido do cliente foi resolvido: ele confirmou que deu certo ou não precisa de mais nada.',
        'horário marcado' => 'O cliente escolheu dia e hora e o horário ficou marcado. O atendimento ainda não aconteceu.',
        'atendido' => 'O cliente veio no horário marcado e foi atendido.',
        'não veio' => 'O cliente tinha horário marcado e não apareceu, nem avisou antes.'
      }.freeze

      def self.criteria_for(stage_name)
        key = stage_name.to_s.strip.downcase
        TEMPLATES[key] || TEMPLATES[key.gsub(/\s+/, ' ')]
      end

      def self.metadata_for(stage_name)
        criteria = criteria_for(stage_name)
        return {} if criteria.blank?

        { 'ai_criteria' => criteria }
      end
    end
  end
end
