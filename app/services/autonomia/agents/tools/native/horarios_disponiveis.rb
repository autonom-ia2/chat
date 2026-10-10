# HORÁRIOS LIVRES DA AGENDA para a IA oferecer ao cliente (#1196, F3, J6-A1).
#
# Síncrona e só de leitura: roda no turno, com o modelo esperando, e também no Testar (não precisa de conversa).
# Devolve até seis inícios livres no fuso da página, pela mesma regra da página pública naquele momento
# (`Crm::BookingV2::Slots`, o mesmo responsável). Com `data`, os do dia; sem ela, os próximos dias, dois por dia.
# Dia pedido sem vaga devolve os próximos livres, dizendo que aquele dia está cheio.
#
# Nenhuma regra aqui lê o que o cliente escreveu (RA-09): o modelo traduz "quinta à tarde" em `data`, e a escolha
# entre as opções também é dele.
class Autonomia::Agents::Tools::Native::HorariosDisponiveis < Autonomia::Agents::Tools::Native::Base
  include Autonomia::Agents::Tools::Native::Agenda

  DATA_INVALIDA = 'A data precisa estar no formato AAAA-MM-DD. Mande de novo, ou mande sem data para ver os próximos dias.'.freeze
  INSTRUCAO = 'Ofereça 2 ou 3 destes horários ao cliente, com dia da semana e hora, e nunca outro. Ao marcar, use o ' \
              'horário exatamente como está aqui.'.freeze

  class << self
    def slug
      'horarios_disponiveis'
    end

    def tool_name
      'Horários disponíveis'
    end

    def description
      'Consulta os horários livres da agenda deste atendimento. Use quando o cliente quiser marcar uma conversa ou ' \
        'reunião, antes de oferecer qualquer horário. Devolve até 6 opções reais no fuso da agenda.'
    end

    def params
      [
        { 'name' => 'data', 'type' => 'string', 'required' => false,
          'description' => 'Dia que o cliente pediu, no formato AAAA-MM-DD. null para os próximos dias livres.' },
        { 'name' => 'duracao_minutos', 'type' => 'integer', 'required' => false,
          'description' => 'Duração em minutos, só se o cliente pediu uma diferente. null usa a duração padrão.' }
      ]
    end

    def args_registraveis
      %w[data duracao_minutos]
    end

    def available_for?(agent)
      Autonomia::Agents::Tools::Native::Agenda.disponivel?(agent)
    end
  end

  def call
    recusa = recusa_da_pagina
    return recusa if recusa

    duracao = duracao_pedida
    return duracao_invalida if duracao.nil?

    dia = dia_pedido
    return parametro_invalido(DATA_INVALIDA) if params['data'].present? && dia.nil?

    responder(dia, duracao)
  end

  private

  def dia_pedido
    Date.iso8601(params['data'].to_s)
  rescue Date::Error
    nil
  end

  def responder(dia, duracao)
    opcoes = dia ? horarios(dia: dia, duracao: duracao) : []
    cheio = dia.present? && opcoes.empty?
    opcoes = horarios(dia: nil, duracao: duracao) if opcoes.empty?
    return recusa_sem_horarios if opcoes.empty?

    descrever(opcoes, duracao, cheio ? dia : nil)
  end

  def descrever(opcoes, duracao, dia_cheio)
    aviso = dia_cheio ? "Não há horário livre em #{dia_cheio.strftime('%d/%m')}. Estes são os próximos livres. " : ''
    [
      "#{aviso}Horários livres (fuso #{fuso.tzinfo.name}, #{duracao} minutos):",
      *opcoes.map { |iso| opcao(iso) },
      "Locais possíveis: #{descricao_dos_locais}.",
      INSTRUCAO
    ].join("\n")
  end
end
