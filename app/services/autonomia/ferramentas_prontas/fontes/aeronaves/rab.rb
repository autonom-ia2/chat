# A aeronave no RAB baixado (#2858, F5): a linha da matrícula (a ANAC repete algumas; vão todas, no máximo `MAXIMO`).
# Os campos saem na ordem de quem lê (`ORDEM`: o que é, o registro, os donos): o jsonb do banco guarda as chaves na
# ordem dele, não na nossa.
class Autonomia::FerramentasProntas::Fontes::Aeronaves::Rab < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'rab'.freeze
  BASE = 'aeronaves'.freeze
  MAXIMO = 5
  ORDEM = %w[matricula fabricante modelo tipo_icao ano_de_fabricacao numero_de_serie categoria operacao motor assentos
             passageiros_no_maximo peso_maximo_de_decolagem_kg situacao cancelada_em motivo_do_cancelamento
             certificado_de_aeronavegabilidade_valido_ate gravames proprietarios_empresas outros_proprietarios
             operadores_empresas outros_operadores].freeze
  EMPRESAS = %w[proprietarios_empresas operadores_empresas].freeze

  def buscar(_consulta, params)
    escopo = da_base(Autonomia::FerramentasProntas::Bases::Aeronave).where(matricula: params.fetch('matricula')).order(:id)
    com_data(listar(escopo, 'aeronaves', MAXIMO) { |item| ficha(item) })
  end

  private

  # A ficha na `ORDEM`; campo novo que não está nela vai no fim, sem sumir. A matrícula sai com o hífen ("PR-XYZ") e o
  # CNPJ das empresas, com a máscara.
  def ficha(item)
    dados = { 'matricula' => Autonomia::FerramentasProntas::Fontes::Aeronaves.matricula_legivel(item.matricula) }.merge(item.dados)
    dados.slice(*ORDEM).merge(dados.except(*ORDEM)).merge(empresas(dados))
  end

  def empresas(dados)
    dados.slice(*EMPRESAS).transform_values do |lista|
      lista.map { |empresa| empresa.key?('cnpj') ? empresa.merge('cnpj' => cnpj_formatado(empresa['cnpj'])) : empresa }
    end
  end
end
