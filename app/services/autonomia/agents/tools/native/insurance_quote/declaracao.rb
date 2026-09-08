# O CONTRATO COM O MODELO — o que ele lê para decidir usar a ferramenta, e o que pode escrever.
#
# Separado do comportamento porque são coisas que mudam por motivos diferentes: a descrição e os
# parâmetros mudam quando o vocabulário do agente muda; `start` e `poll` mudam quando o fluxo de
# cotação muda. Juntos, cada ajuste de texto abria o arquivo que decide o que vai para o cliente.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Declaracao
  extend ActiveSupport::Concern

  # `dados` viaja como TEXTO JSON, e não como objeto. O schema de função exige `strict` com
  # `additionalProperties: false`, e um objeto de forma livre não tem como ser declarado ali — cada
  # ramo tem os seus campos, que é o ponto desta ferramenta. Texto é o único tipo que atravessa; a
  # ferramenta parseia e diz com clareza quando o JSON não presta.
  COMUNS = [
    { 'name' => 'produto', 'type' => 'string',
      'description' => 'Ramo a cotar: auto, residencial, condominio, empresarial, ' \
                       'fianca_locaticia, viagem, acidentes_pessoais, vida, vida_global, celular ' \
                       'ou bike.' },
    { 'name' => 'cpf', 'type' => 'string', 'required' => false,
      'description' => 'CPF ou CNPJ do segurado, só números ou formatado.' },
    { 'name' => 'nome', 'type' => 'string', 'required' => false,
      'description' => 'Nome do segurado, se o cliente já informou.' },
    { 'name' => 'cep', 'type' => 'string', 'required' => false,
      'description' => 'CEP: onde o carro dorme (auto) ou onde fica o imóvel.' },
    { 'name' => 'numero', 'type' => 'string', 'required' => false,
      'description' => 'Número do endereço, se o cliente informou.' },
    { 'name' => 'dados', 'type' => 'string', 'required' => false,
      'description' => 'JSON com o que o cliente informou nos ramos que não são auto, usando os ' \
                       'nomes de campo que a ferramenta pedir. Exemplo para bike: ' \
                       '{"configuracoes":{"marca":"Caloi","valorMercado":8000}}. Mande {} na ' \
                       'primeira vez para descobrir o que perguntar.' }
  ].freeze

  # SÓ AUTO TEM VEÍCULO E BÔNUS. Ficam como parâmetros próprios, e não dentro do JSON, porque auto é
  # o ramo mais pedido e um campo dedicado é mais difícil de o modelo errar do que uma chave dentro
  # de texto.
  DE_AUTO = [
    { 'name' => 'placa', 'type' => 'string', 'required' => false,
      'description' => 'Placa do veículo (7 caracteres). Só em auto.' },
    { 'name' => 'renovacao', 'type' => 'boolean', 'required' => false,
      'description' => 'true quando o cliente JÁ TEM seguro e está renovando. Só marque com ' \
                       'confirmação dele; na dúvida, deixe em branco. Só em auto.' },
    { 'name' => 'bonus', 'type' => 'integer', 'required' => false,
      'description' => ::Autonomia::Insurance::AutoRenewal::BONUS_DESC },
    { 'name' => 'sinistros', 'type' => 'integer', 'required' => false,
      'description' => ::Autonomia::Insurance::AutoRenewal::SINISTROS_DESC }
  ].freeze

  DESCRICAO = 'Cota seguro de AUTOMÓVEL, RESIDENCIAL, CONDOMÍNIO, EMPRESARIAL, ALUGUEL/FIANÇA, ' \
              'VIAGEM, ACIDENTES PESSOAIS, VIDA, VIDA EM GRUPO, CELULAR ou BICICLETA nas ' \
              'seguradoras que esta corretora atende. Para auto, precisa do CPF, da placa e do ' \
              'CEP de pernoite. Nos outros ramos, informe o que o cliente já deu; se faltar algo, ' \
              'a ferramenta responde exatamente o que perguntar, sem consumir cotação.'.freeze

  # NÃO PROMETA O QUE AINDA NÃO ACONTECEU. Este texto volta ao modelo em `Bound#accept_async`, que
  # roda ANTES de qualquer conferência: nada foi enviado a seguradora nenhuma ainda, e o pedido pode
  # ser recusado logo em seguida por falta de dado, por conexão fora do ar ou por prazo. Quando ele
  # dizia "Cotação enviada às seguradoras", o agente anunciava sucesso e cinco segundos depois se
  # desmentia na frente do cliente — em 08/09/2026, com estas duas mensagens seguidas.
  ACEITA = 'Pedido de cotação recebido e em conferência. Avise o cliente que você está cuidando ' \
           'disso e que volta aqui com notícia. NÃO afirme que já foi enviada às seguradoras, e ' \
           'não invente valores, prazos nem nomes de seguradora.'.freeze

  ESPERANDO = 'Estou consultando as seguradoras agora. Assim que os primeiros preços chegarem, ' \
              'mando aqui.'.freeze

  FALHOU = 'Não consegui concluir a cotação agora. Um atendente vai retomar daqui.'.freeze

  class_methods do
    def slug
      'cotar_seguro'
    end

    def tool_name
      'Cotar seguro'
    end

    # Cotar leva minutos: o turno não pode esperar. `start` submete e volta com o id; `poll` consulta.
    def async?
      true
    end

    def description
      DESCRICAO
    end

    def params
      COMUNS + DE_AUTO
    end

    # Ferramenta que depende de recurso não configurado não deve nem aparecer no prompt: melhor não
    # oferecer do que oferecer e falhar na frente do cliente.
    def available_for?(agent)
      return false unless ::Autonomia::Insurance::Config.enabled?(agent.account)

      ::Autonomia::Insurance::Connection.for_account(agent.account).any?(&:ready?)
    rescue StandardError
      false
    end

    def accepted_message
      ACEITA
    end

    def waiting_message
      ESPERANDO
    end

    def failure_message
      FALHOU
    end
  end
end
