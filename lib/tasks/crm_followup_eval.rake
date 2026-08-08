# Régua do cérebro de follow-up: roda o FollowUpComposer real contra um banco de conversas e
# confere a decisão (de quem é a vez, tipo de mensagem, enviar ou não).
#
#   bundle exec rake crm:followup_eval
#
# FORA DO CI de propósito: cada caso é uma chamada paga à API. Rode à mão antes de mexer no prompt
# e depois, comparando os dois resultados.
#
# Os casos versionados são SINTÉTICOS — derivados de conversas reais, com nomes e detalhes trocados.
# Nunca commite transcrição de cliente aqui. Para rodar contra conversas reais, aponte
# FOLLOWUP_EVAL_CASES para um arquivo fora do versionamento.

# Um caso do banco: monta o contexto, chama o cérebro e compara com o esperado.
class FollowUpEvalCase
  LINHA = '%-32<nome>s %-6<veredito>s %-9<owner>s %-16<kind>s %<detalhe>s'.freeze

  def initialize(kase, card, credential)
    @kase = kase
    @card = card
    @credential = credential
  end

  def run
    out = compose
    ok = matches?(out)
    { ok: ok,
      linha: format(LINHA, nome: nome, veredito: ok ? 'ok' : 'FALHA',
                           owner: out['next_action_owner'].to_s, kind: out['message_kind'].to_s,
                           detalhe: out['message_body'].to_s.truncate(70)) }
  rescue StandardError => e
    { ok: false,
      linha: format(LINHA, nome: nome, veredito: 'ERRO', owner: '-', kind: '-',
                           detalhe: "#{e.class}: #{e.message.to_s.truncate(60)}") }
  end

  private

  def nome
    @kase['nome'].to_s.truncate(31)
  end

  def compose
    Crm::Ai::FollowUpComposer.new(
      card: @card,
      client: Crm::Ai::ResponsesClient.new(credential: @credential, feature: 'follow_up'),
      context: context,
      mode: :free_form,
      tone_instructions: @kase['tone_instructions'].to_s
    ).perform
  end

  def context
    messages = @kase['messages'].map(&:symbolize_keys)
    {
      summary: @kase['summary'].to_s,
      recent_messages: messages,
      current_stage: { id: 0, name: @kase['stage'].to_s.presence || 'Em negociação' },
      conversation_state: { status: 'open', assigned_to_human: true,
                            last_human_agent_at: messages.last[:created_at] },
      temporal: { timezone: 'America/Sao_Paulo', now_local: @kase['agora'].to_s, weekday: 'Thursday',
                  default_hour: 9 }
    }
  end

  # Campo ausente no esperado significa "tanto faz" — só o que foi declarado é cobrado.
  def matches?(out)
    expected = @kase['esperado'].to_h
    %w[should_send closure_detected next_action_owner message_kind].all? do |field|
      !expected.key?(field) || out[field].to_s == expected[field].to_s
    end
  end
end

namespace :crm do
  desc 'Avalia as decisões do cérebro de follow-up contra um banco de conversas'
  task followup_eval: :environment do
    path = ENV.fetch('FOLLOWUP_EVAL_CASES', Rails.root.join('lib/tasks/crm_followup_cases.json').to_s)
    credential = { api_key: ENV.fetch('OPENAI_API_KEY'), api_base: 'https://api.openai.com', source: :env }
    card = Struct.new(:id, :title).new(0, 'Lead')

    results = JSON.parse(File.read(path)).map { |kase| FollowUpEvalCase.new(kase, card, credential).run }

    puts format(FollowUpEvalCase::LINHA, nome: 'CASO', veredito: 'VERD', owner: 'VEZ', kind: 'TIPO',
                                         detalhe: 'MENSAGEM')
    results.each { |r| puts r[:linha] }
    aprovados = results.count { |r| r[:ok] }
    puts "\n#{aprovados}/#{results.size} de acordo com o esperado"
    abort('eval reprovado') unless aprovados == results.size
  end
end
