import {
  paraItem,
  acaoDoItem,
  semRepeticoes,
  tipoDoEvento,
} from './itensDoCalendario';

const FUSO = 'America/Sao_Paulo';
const AGORA = new Date('2026-10-14T18:00:00Z');
const item = evento => paraItem(evento, { fuso: FUSO, agora: AGORA });

describe('itensDoCalendario', () => {
  it('o vencimento é dia todo, no dia que o back manda, sem hora', () => {
    const vencimento = item({
      id: 'expected_close_1',
      event_type: 'expected_close',
      starts_at: '2026-10-20T00:00:00Z',
      all_day: true,
      date: '2026-10-20',
    });
    expect(vencimento).toMatchObject({
      tipo: 'fechar',
      diaTodo: true,
      chave: '2026-10-20',
      atrasado: false,
      podeConcluir: false,
    });
  });

  it('lembrete que passou atrasa; o calculado de uma repetição não', () => {
    const passou = {
      id: 'follow_up_1',
      event_type: 'follow_up_reminder_only',
      starts_at: '2026-10-13T13:00:00Z',
      status: 'pending',
    };
    expect(item(passou)).toMatchObject({ atrasado: true, podeConcluir: true });
    expect(item({ ...passou, virtual: true })).toMatchObject({
      atrasado: false,
      podeConcluir: false,
    });
    expect(item({ ...passou, status: 'done' }).atrasado).toBe(false);
  });

  it('traz o cliente do próprio evento', () => {
    const lembrete = item({
      id: 'follow_up_2',
      event_type: 'follow_up_reminder_only',
      starts_at: '2026-10-14T19:30:00Z',
      contact_name: 'Mariana Costa',
      contact_phone: '+5511987654321',
    });
    expect(lembrete.contato).toEqual({
      nome: 'Mariana Costa',
      telefone: '+5511987654321',
    });
    expect(lembrete.chave).toBe('2026-10-14');
    expect(lembrete.minutos).toBe(16 * 60 + 30);
  });

  it('uma ação por item: conversa antes de ligar, ligar antes de ver', () => {
    const base = {
      id: 'follow_up_3',
      event_type: 'follow_up_reminder_only',
      starts_at: '2026-10-14T19:30:00Z',
    };
    const hoje = '2026-10-14';
    expect(
      acaoDoItem(
        item({ ...base, conversation_display_id: 7, contact_phone: '+55' }),
        { hoje }
      )
    ).toMatchObject({ chave: 'ABRIR_CONVERSA', conversa: 7 });
    expect(
      acaoDoItem(item({ ...base, contact_phone: '+55' }), { hoje })
    ).toMatchObject({ chave: 'LIGAR', link: 'tel:+55' });
    expect(acaoDoItem(item(base), { hoje }).chave).toBe('VER');
  });

  it('reunião com link só oferece "Entrar" no dia', () => {
    const reuniao = {
      id: 'meeting_1',
      event_type: 'meeting',
      starts_at: '2026-10-14T21:00:00Z',
      online_meeting_url: 'https://meet.example/abc',
    };
    expect(acaoDoItem(item(reuniao), { hoje: '2026-10-14' }).chave).toBe(
      'ENTRAR'
    );
    expect(acaoDoItem(item(reuniao), { hoje: '2026-10-13' }).chave).toBe(
      'VER_REUNIAO'
    );
    expect(
      acaoDoItem(item({ ...reuniao, event_type: 'external' }), {
        hoje: '2026-10-14',
      })
    ).toBeNull();
  });

  it('nos próximos dias, a repetição aparece uma vez só', () => {
    const lista = [
      { id: 'a', evento: { series_id: 5 } },
      { id: 'b', evento: { series_id: 5 } },
      { id: 'c', evento: {} },
    ];
    expect(semRepeticoes(lista).map(i => i.id)).toEqual(['a', 'c']);
  });

  it('mensagem que sai sozinha é do tipo mensagem', () => {
    expect(tipoDoEvento({ event_type: 'follow_up_auto_send_message' })).toBe(
      'mensagem'
    );
  });
});
