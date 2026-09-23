# OS EVENTOS DA COTAÇÃO E OS FATOS QUE O MODELO LÊ SOBRE CADA UM (PR C).
#
# Até aqui esta ferramenta publicava, pelo motor, as frases que o cliente lia: a constante nossa ou a frase que
# o especialista escrevia no pedido (o nó `frases_ao_cliente`). Agora ela diz o QUE aconteceu e o motor dispara
# o evento (`Tools::Evento`); quem fala é a Lia, num turno de modelo, com a voz dela. Nada daqui chega ao cliente
# como está: é texto para o MODELO.
#
# OS FATOS SÃO DE CLASSE e saem da LINHA (`run.handle`): o evento de falha sai mesmo com o agente apagado. Nunca
# levam dado pessoal: nomes de campo, o motivo que o adapter escreveu, a lista de ramos, o fato da renovação sem
# bônus. O que a busca do segurado achou não entra (ela só roda na conferência, e não deixa nada no handle).
module Autonomia::Agents::Tools::Native::InsuranceQuote::Eventos
  extend ActiveSupport::Concern

  # O motivo da recusa do envio -> o tipo do evento. Formulário indisponível não é dado que a pessoa deve: o evento é
  # `falhou`, com fatos próprios (`SEM_FORMULARIO`), porque pedir de novo daria a mesma recusa. Motivo fora da tabela
  # também é `falhou`.
  EVENTO_DA_RECUSA = {
    'faltam_dados' => 'falta_dado', 'json_invalido' => 'falta_dado', 'sem_veiculo' => 'falta_dado',
    'ramo_desconhecido' => 'ramo_desconhecido', 'formulario_indisponivel' => 'falhou'
  }.freeze

  FATOS = {
    'cotacao_comecou' => 'A cotação pedida nesta conversa foi recebida e está sendo feita agora. Ainda não se sabe o que as ' \
                         'seguradoras vão responder, e o resultado chega nesta conversa quando ficar pronto.',
    'concluida' => 'A cotação terminou, e o comparativo em PDF com as opções acabou de ser enviado nesta conversa, logo ' \
                   'acima. Os valores de cada seguradora estão com o especialista, que os lê sem cotar de novo.',
    'valores_guardados' => 'A cotação terminou com preços, mas o comparativo em PDF não pôde ser enviado. Os valores de cada ' \
                           'seguradora estão guardados com o especialista, e a pessoa pode pedi-los aqui mesmo.',
    # O QUE DEU ERRADO VAI PARA A EQUIPE (decisão do CEO, 23/09/2026). A passagem é do CRM: o gatilho do funil é a
    # própria fala da Lia de que vai encaminhar para alguém da equipe, e aí o CRM atribui a conversa. O prazo esgotado
    # com o comparativo entregue não é erro: a pessoa tem as opções de quem respondeu.
    'falhou' => 'A cotação não pôde ser concluída agora, e nenhuma opção chegou à pessoa. Diga que vai encaminhar para ' \
                'alguém da equipe continuar, sem prazo e sem narrar o que falhou.',
    # A INCERTA NÃO OFERECE REFAZER (revisão da chat#608): a cotação pode existir e já ter sido paga no portal, e o
    # pedido novo não é barrado como repetido (a execução fecha sem entrega). Não se sabe se deu: não se diz que não deu.
    'incerta' => 'Não foi possível confirmar se o pedido chegou às seguradoras, e nenhuma opção chegou à pessoa até ' \
                 'agora. Diga que não conseguiu confirmar e que vai encaminhar para alguém da equipe conferir, sem afirmar ' \
                 'que não deu, sem oferecer cotar de novo e sem prazo.',
    'encerrada_por_prazo' => 'A cotação terminou, e o comparativo em PDF com as opções de quem respondeu já está nesta ' \
                             'conversa. Uma ou mais seguradoras não responderam dentro do tempo e ficaram de fora: foi ' \
                             'instabilidade delas, não recusa do risco, e não é motivo para refazer. Os valores de ' \
                             'cada seguradora estão com o especialista, que os lê sem cotar de novo.'
  }.freeze

  # FORMULÁRIO INDISPONÍVEL (revisão da chat#608): pedir de novo daria a mesma recusa, então não se oferece.
  SEM_FORMULARIO = 'A cotação não pôde ser aberta agora: o formulário deste tipo de seguro não está disponível. Nenhuma ' \
                   'opção chegou à pessoa. Não ofereça cotar de novo agora: diga que vai encaminhar para alguém da ' \
                   'equipe continuar, sem prazo.'.freeze

  # Só em renovação de auto cotada sem a classe de bônus. Sem número e sem promessa de desconto: o quanto o bônus
  # abate é decisão de cada seguradora.
  SEM_BONUS = 'Esta renovação foi cotada sem a classe de bônus da apólice atual: os preços são os de quem faz o primeiro ' \
              'seguro. Com a classe de bônus, que está na apólice, a cotação pode ser refeita, e costuma sair melhor.'.freeze
  COM_SEM_BONUS = %w[concluida valores_guardados encerrada_por_prazo].freeze

  FALTA_JSON = 'A cotação não foi aberta: os dados do ramo que o especialista mandou não puderam ser lidos. Confira com o ' \
               'especialista o que falta e pergunte à pessoa só o que ninguém disse ainda.'.freeze
  FALTA_PREFIXO = 'A cotação não foi aberta: falta dado que a pessoa precisa dar. O que a conferência apontou:'.freeze

  class_methods do
    # -> os fatos do evento `tipo` desta execução, para o modelo (`Native::Base.fatos_do_evento`), começando pelo
    # produto: com auto e residencial na mesma conversa, a Lia precisa saber de qual seguro é a notícia.
    def fatos_do_evento(tipo, run)
      "Cotação de #{run.faixa.presence || self::AUTO}. #{fatos_do_tipo(tipo.to_s, run.handle.to_h)}"
    end

    private

    def fatos_do_tipo(tipo, handle)
      case tipo
      when 'falta_dado' then fatos_da_falta(handle)
      when 'ramo_desconhecido' then "A cotação não foi aberta. #{self::RAMO_DESCONHECIDO}"
      when 'falhou' then fatos_da_falha(handle)
      else [FATOS[tipo], (SEM_BONUS if COM_SEM_BONUS.include?(tipo) && handle[self::SEM_BONUS_KEY].present?)].compact.join(' ')
      end
    end

    # Formulário indisponível recusaria de novo: não se oferece pedir outra vez.
    def fatos_da_falha(handle)
      (handle['recusa'] || handle['motivo']).to_s == 'formulario_indisponivel' ? SEM_FORMULARIO : FATOS['falhou']
    end

    # A recusa desta versão traz os `problemas` (campo e motivo, como a conferência os produz); a da versão
    # anterior à PR C só traz os nomes em `faltando`, e o texto velho em `pedido`, que não é reaproveitado.
    def fatos_da_falta(handle)
      motivo = (handle['recusa'] || handle['motivo']).to_s
      return FALTA_JSON if motivo == 'json_invalido'
      return "#{FALTA_PREFIXO} #{self::SEM_VEICULO}" if motivo == 'sem_veiculo'

      "#{FALTA_PREFIXO} #{itens_da_falta(handle).join('; ').presence || 'o adapter não disse qual campo'}."
    end

    def itens_da_falta(handle)
      problemas = Array(handle['problemas']).select { |item| item.is_a?(Hash) }
      return problemas.map { |item| "#{campo_com_rotulo(item['campo'])}: #{item['motivo']}" } if problemas.any?

      Array(handle['faltando']).map { |campo| campo_com_rotulo(campo) }
    end

    def campo_com_rotulo(campo)
      rotulo = self::ROTULOS[campo.to_s]
      rotulo ? "#{campo} (#{rotulo})" : campo.to_s
    end
  end

  private

  # O handle desta execução é o de uma recusa do envio? A versão anterior à PR C gravava o texto em `pedido`.
  def recusa?(handle)
    handle['recusa'].present? || handle['pedido'].present?
  end

  def evento_da_recusa(handle)
    EVENTO_DA_RECUSA.fetch((handle['recusa'] || handle['motivo']).to_s, 'falhou')
  end
end
