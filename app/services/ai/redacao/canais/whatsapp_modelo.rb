# Modelo de mensagem do WhatsApp (#1333, épico #1320): o texto que a Meta revisa antes de aprovar. Primeiro consumidor:
# "Criar com IA" e "Melhorar com IA" da tela de Modelos (`Whatsapp::Templates::Redacao`). Prompt e schema calibrados na
# bateria da Modelos (29/30, 8/8 armadilhas): cada opção traz o corpo em "texto" e, em "whatsapp", cabeçalho, rodapé,
# botões e um nome sugerido, com o tipo previsto (serviço ou divulgação). O tipo é só previsão: quem decide é a Meta.
#
# A conferência é a comum (chaves, pontas, tamanho, base) mais a da Meta, só de estrutura e sem regex:
# corpo até 1024; campos sem palavra entre eles;
# cabeçalho até 60, com no máximo 1 campo e sem campo nas pontas; rodapé até 60 sem campo; até 3 botões de um grupo só
# (respostas rápidas, ou até 2 links e 1 telefone), texto até 25, campo só em link/telefone; nome em a-z, 0-9 e "_".
# "No máximo 5 campos, um para cada 4 palavras" fica só no prompt: é escolha nossa (a Meta não publica número), e no
# "melhorar" a base já pode ter mais campos que isso, que a opção é obrigada a manter.
class Ai::Redacao::Canais::WhatsappModelo < Ai::Redacao::Canais::Base
  CORPO_MAXIMO = 1024
  CABECALHO_MAXIMO = 60
  RODAPE_MAXIMO = 60
  BOTAO_MAXIMO = 25
  BOTOES_MAXIMO = 3
  NOME_MAXIMO = 40
  RESPOSTA = 'resposta_rapida'.freeze
  LINK = 'link'.freeze
  TELEFONE = 'telefone'.freeze
  TIPOS_DE_BOTAO = [RESPOSTA, LINK, TELEFONE].freeze
  LIMITE_POR_TIPO = { LINK => 2, TELEFONE => 1 }.freeze
  LETRAS_DO_NOME = [*'a'..'z', *'0'..'9', '_'].to_set.freeze

  class << self
    def nome
      'whatsapp_modelo'
    end

    # O cabeçalho e o campo de cada botão também levam chave (o do botão vira `{{chave}}` só para a conferência).
    def textos_com_chaves(opcao)
      whatsapp = whatsapp_de(opcao)
      [opcao['texto'].to_s, whatsapp['cabecalho'].to_s] +
        botoes_de(whatsapp).filter_map { |botao| "{{#{botao['chave']}}}" if botao['chave'].present? }
    end

    def normalizar_opcao(opcao)
      whatsapp = whatsapp_de(opcao)
      super.merge(
        chaves_usadas: textos_com_chaves(opcao).flat_map { |texto| Ai::Redacao::Chaves.extrair(texto) }.uniq,
        certeza_categoria: opcao['certeza_categoria'],
        whatsapp: {
          cabecalho: whatsapp['cabecalho'].to_s.strip.presence, rodape: whatsapp['rodape'].to_s.strip.presence,
          nome_sugerido: whatsapp['nome_sugerido'].to_s,
          botoes: botoes_de(whatsapp).map { |botao| { tipo: botao['tipo'], texto: botao['texto'].to_s.strip, chave: botao['chave'] } }
        }
      )
    end

    private

    def problema_do_canal(opcao, chaves:, **)
      whatsapp = whatsapp_de(opcao)
      problema_do_corpo(opcao['texto'].to_s) || problema_do_cabecalho(whatsapp['cabecalho']) ||
        problema_do_rodape(whatsapp['rodape']) || problema_dos_botoes(botoes_de(whatsapp), chaves) ||
        problema_do_nome(whatsapp['nome_sugerido'])
    end

    def problema_do_corpo(texto)
      return :longo if texto.length > CORPO_MAXIMO

      :campos_colados if campos_colados?(Ai::Redacao::Chaves.partes(texto))
    end

    # Dois campos com só espaço ou pontuação entre eles.
    def campos_colados?(partes)
      partes.each_cons(2).any? { |a, b| a.chave? && b.chave? } ||
        partes.each_cons(3).any? { |a, meio, b| a.chave? && b.chave? && !texto_com_letra?(meio) }
    end

    def problema_do_cabecalho(cabecalho)
      return if cabecalho.blank?

      :cabecalho_invalido if cabecalho.length > CABECALHO_MAXIMO || Ai::Redacao::Chaves.malformado?(cabecalho) ||
                             campos_do_cabecalho_ruins?(Ai::Redacao::Chaves.partes(cabecalho))
    end

    # No máximo 1 campo, e nunca na ponta.
    def campos_do_cabecalho_ruins?(partes)
      partes.count(&:chave?) > 1 || partes.first.chave? || partes.last.chave?
    end

    def problema_do_rodape(rodape)
      return if rodape.blank?

      :rodape_invalido if rodape.length > RODAPE_MAXIMO || rodape.include?(Ai::Redacao::Chaves::ABRE) ||
                          rodape.include?(Ai::Redacao::Chaves::FECHA)
    end

    def problema_dos_botoes(botoes, chaves)
      return :botoes_invalidos if botoes.size > BOTOES_MAXIMO || botoes.any? { |botao| botao_invalido?(botao, chaves) }

      problema_dos_grupos(botoes.pluck('tipo'))
    end

    # Um grupo só: respostas rápidas, ou até 2 links e 1 telefone.
    def problema_dos_grupos(tipos)
      return :botoes_misturados if tipos.include?(RESPOSTA) && tipos.uniq != [RESPOSTA]

      :botoes_invalidos if LIMITE_POR_TIPO.any? { |tipo, maximo| tipos.count(tipo) > maximo }
    end

    def botao_invalido?(botao, chaves)
      texto = botao['texto'].to_s.strip
      return true unless TIPOS_DE_BOTAO.include?(botao['tipo']) && texto.present? && texto.length <= BOTAO_MAXIMO
      return true if texto.include?(Ai::Redacao::Chaves::ABRE) || texto.include?(Ai::Redacao::Chaves::FECHA)

      chave_do_botao_invalida?(botao, chaves)
    end

    # Resposta rápida não tem campo; o campo de link ou telefone precisa estar na lista.
    def chave_do_botao_invalida?(botao, chaves)
      chave = botao['chave']
      return false if chave.nil?

      botao['tipo'] == RESPOSTA || Array(chaves[:permitidas]).exclude?(chave)
    end

    def problema_do_nome(nome)
      nome = nome.to_s
      :nome_invalido if nome.empty? || nome.length > NOME_MAXIMO || nome.each_char.any? { |char| LETRAS_DO_NOME.exclude?(char) }
    end

    def whatsapp_de(opcao)
      opcao['whatsapp'].is_a?(Hash) ? opcao['whatsapp'] : {}
    end

    def botoes_de(whatsapp)
      Array(whatsapp['botoes']).select { |botao| botao.is_a?(Hash) }
    end

    def campos_da_opcao(_permitidas)
      {
        whatsapp: {
          type: 'object', additionalProperties: false, required: %w[cabecalho rodape botoes nome_sugerido],
          properties: {
            cabecalho: { type: %w[string null] }, rodape: { type: %w[string null] },
            botoes: { type: 'array', maxItems: BOTOES_MAXIMO, items: { '$ref': '#/$defs/botao' } },
            nome_sugerido: { type: 'string' }
          }
        }
      }
    end
  end

  # O `enum` da chave do botão depende das permitidas, então o schema do botão entra por chamada.
  def self.schema(permitidas:, opcoes:)
    botao = {
      type: 'object', additionalProperties: false, required: %w[tipo texto chave],
      properties: {
        tipo: { type: 'string', enum: TIPOS_DE_BOTAO }, texto: { type: 'string' },
        chave: { type: %w[string null], enum: permitidas + [nil] }
      }
    }
    super.deep_merge(schema: { '$defs': { botao: botao } })
  end
end
