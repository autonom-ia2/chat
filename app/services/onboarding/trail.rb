# Carrega e valida a trilha de onboarding (config/onboarding/trilha.yml).
# Fonte única dos passos: tela Primeiros passos, Central de Ajuda, Guia e tours
# leem daqui. Campo faltando ou valor fora do esperado derruba o boot, para o
# erro aparecer no deploy e não na tela do cliente.
class Onboarding::Trail
  class InvalidDefinition < StandardError; end

  PATH = Rails.root.join('config/onboarding/trilha.yml')
  CAMPOS_OBRIGATORIOS = %w[id ordem titulo por_que rota alvo_destaque verificacao fluxos_guia artigo pulavel perfis
                           pre_requisitos].freeze
  PERFIS_VALIDOS = %w[administrator agent].freeze

  Passo = Struct.new(:id, :ordem, :titulo, :por_que, :rota, :rota_params, :alvo_destaque, :verificacao, :fluxos_guia,
                     :video, :artigo, :pulavel, :perfis, :pre_requisitos, keyword_init: true) do
    def pulavel?
      pulavel == true
    end

    def visivel_para?(perfil)
      perfis.include?(perfil.to_s)
    end
  end

  class << self
    def passos
      @passos ||= carregar
    end

    def find(id)
      passos.find { |passo| passo.id == id.to_s }
    end

    def para_perfil(perfil)
      passos.select { |passo| passo.visivel_para?(perfil) }
    end

    def recarregar!
      @passos = nil
      passos
    end

    private

    def carregar
      dados = YAML.safe_load_file(PATH)
      raise InvalidDefinition, 'trilha.yml precisa de uma lista em `passos`' unless dados.is_a?(Hash) && dados['passos'].is_a?(Array)

      passos = dados['passos'].map { |bruto| construir(bruto) }
      validar_conjunto!(passos)
      passos.sort_by(&:ordem)
    end

    def construir(bruto)
      raise InvalidDefinition, "passo precisa ser um mapa, veio #{bruto.class}" unless bruto.is_a?(Hash)

      faltando = CAMPOS_OBRIGATORIOS - bruto.keys
      raise InvalidDefinition, "passo #{bruto['id'].inspect} sem os campos: #{faltando.join(', ')}" if faltando.any?

      validar_campos!(bruto)
      Passo.new(**bruto.symbolize_keys.slice(*Passo.members))
    end

    def validar_campos!(bruto)
      id = bruto['id'].inspect
      raise InvalidDefinition, "passo #{id} com ordem não numérica" unless bruto['ordem'].is_a?(Integer)
      raise InvalidDefinition, "passo #{id} com pulavel fora de true/false" unless [true, false].include?(bruto['pulavel'])
      raise InvalidDefinition, "passo #{id} sem perfil" if Array(bruto['perfis']).empty?

      perfis_invalidos = Array(bruto['perfis']) - PERFIS_VALIDOS
      raise InvalidDefinition, "passo #{id} com perfil desconhecido: #{perfis_invalidos.join(', ')}" if perfis_invalidos.any?

      %w[titulo por_que rota alvo_destaque verificacao artigo].each do |campo|
        raise InvalidDefinition, "passo #{id} com #{campo} em branco" if bruto[campo].to_s.strip.empty?
      end
    end

    def validar_conjunto!(passos)
      exigir_unico!(passos.map(&:id), 'id')
      exigir_unico!(passos.map(&:ordem), 'ordem')
      exigir_regra_conhecida!(passos)
    end

    def exigir_unico!(valores, nome)
      return if valores.uniq.size == valores.size

      raise InvalidDefinition, "trilha.yml com #{nome} repetido"
    end

    def exigir_regra_conhecida!(passos)
      desconhecidas = passos.map(&:verificacao) - Onboarding::Progress::REGRAS.keys.map(&:to_s)
      return if desconhecidas.empty?

      raise InvalidDefinition, "trilha.yml com verificação sem regra: #{desconhecidas.join(', ')}"
    end
  end
end
