# Avisos do agendamento fora da janela de 24 h (#1524, épico #1585): um modelo FIXO por tipo de aviso (ao marcar, horário
# mudou, 1 dia antes, 1 hora antes), com os botões "Ver meu horário" (URL `/b/<código>` na base do ambiente) e "Parar
# avisos" (resposta rápida com o payload `stop_notices`, que o `Crm::BookingNoticeStopReplyListener` consome).
#
# Redação de UTILIDADE (pesquisa do #1585): cita o horário marcado e o próximo passo, sem oferta, desconto ou urgência.
# Texto fixo no fim, porque a variável não pode fechar o corpo. O nome do negócio não entra: o `EXEMPLOS` do catálogo
# (`Finalidades`) não tem exemplo para `minha_empresa.nome`, e a Meta pede um por variável.
#
# Nomes `_v2`: os `_v1` (com o link no `{{3}}`, `Crm::BookingV2::NoticeTemplates::Catalog`) continuam como estão.
# Só leitura por enquanto: quem cria na Meta depende da autorização do dono (#1586).
module Whatsapp::Templates::Finalidades::Agendamento
  CAMPOS = %w[cliente.primeiro_nome horario.data_hora].freeze
  FIM = 'Para ver os detalhes, mudar ou cancelar, toque em "Ver meu horário". Se não quiser mais receber estes avisos, ' \
        'toque em "Parar avisos".'.freeze
  BOTOES = [
    { tipo: 'url', texto: 'Ver meu horário', url: { base: :booking_invite, caminho: '/b/{{1}}' }.freeze,
      campo: 'horario.link_codigo' }.freeze,
    { tipo: 'quick_reply', texto: 'Parar avisos', payload: 'stop_notices' }.freeze
  ].freeze
  # Tipo do aviso (`Crm::MeetingNotice::KINDS`) => finalidade deste arquivo.
  POR_TIPO = {
    'booked' => 'agendamento_ao_marcar', 'rescheduled' => 'agendamento_horario_mudou',
    'day_before' => 'agendamento_1_dia_antes', 'hour_before' => 'agendamento_1_hora_antes'
  }.freeze

  def self.variante(nome, amigavel, texto)
    { [] => { nome: nome, amigavel: amigavel, campos: CAMPOS, botoes: BOTOES, texto: "#{texto} #{FIM}" } }
  end

  FINALIDADES = {
    'agendamento_ao_marcar' => {
      dono: 'agendamento', opcoes: [],
      variantes: variante('agendamento_ao_marcar_v2', 'Agendamento: ao marcar', 'Olá, {{1}}! Seu horário está marcado para {{2}}.')
    },
    'agendamento_horario_mudou' => {
      dono: 'agendamento', opcoes: [],
      variantes: variante('agendamento_horario_mudou_v2', 'Agendamento: horário mudou', 'Olá, {{1}}! Seu horário mudou para {{2}}.')
    },
    'agendamento_1_dia_antes' => {
      dono: 'agendamento', opcoes: [],
      variantes: variante('agendamento_1_dia_antes_v2', 'Agendamento: 1 dia antes', 'Olá, {{1}}! Lembrete: seu horário é amanhã, {{2}}.')
    },
    'agendamento_1_hora_antes' => {
      dono: 'agendamento', opcoes: [],
      variantes: variante('agendamento_1_hora_antes_v2', 'Agendamento: 1 hora antes',
                          'Olá, {{1}}! Lembrete: seu horário começa em 1 hora ({{2}}).')
    }
  }.freeze
end
