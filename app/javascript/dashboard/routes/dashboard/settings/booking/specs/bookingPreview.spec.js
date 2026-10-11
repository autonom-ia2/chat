import {
  previewDays,
  previewDurations,
  previewEarliest,
  previewZone,
  publicPageFrom,
} from '../bookingPreview';
import { brandFormPatch, pageToForm, presetColor } from '../bookingPageForm';

// O formulário do assistente vira o que a página pública recebe (#1289).
const page = {
  title: 'Visita',
  description: 'Conheça a loja.',
  duration_minutes: 60,
  slot_durations: [30, 60],
  booking_window_days: 7,
  people: [
    { id: 4, name: 'Maria', avatar_url: 'https://cdn.exemplo.com/maria.png' },
    { id: 5, name: 'Bia', avatar_url: null },
  ],
  working_hours: { start_hour: 8, end_hour: 12, weekdays: [1, 3] },
  brand: { color: '#ffe066', headline: 'Oi', logo_align: 'center' },
  logo_url: 'https://cdn.exemplo.com/logo.png',
  photo_url: null,
};

describe('bookingPreview', () => {
  it('monta a página pública com marca, lado da logo e a primeira pessoa', () => {
    expect(publicPageFrom(pageToForm(page), page)).toEqual({
      title: 'Visita',
      description: 'Conheça a loja.',
      agent_name: 'Maria',
      agent_photo_url: 'https://cdn.exemplo.com/maria.png',
      duration_minutes: 60,
      brand: {
        color: '#ffe066',
        headline: 'Oi',
        logo_align: 'center',
        logo_url: 'https://cdn.exemplo.com/logo.png',
        photo_url: null,
      },
    });
  });

  it('página sem ninguém escolhido não quebra', () => {
    const empty = { ...page, people: [] };
    const result = publicPageFrom(pageToForm(empty), empty);
    expect(result.agent_name).toBe('');
    expect(result.agent_photo_url).toBeNull();
  });

  it('durações sem repetir, da menor para a maior', () => {
    expect(previewDurations(pageToForm(page))).toEqual([30, 60]);
  });

  it('só os dias da semana em que a página atende', () => {
    // 12/10/2026 é segunda-feira.
    const days = previewDays(
      pageToForm(page),
      { ...page, preview: { timezone: 'America/Sao_Paulo' } },
      new Date('2026-10-12T12:00:00Z')
    );
    expect(days).toEqual(['2026-10-12', '2026-10-14', '2026-10-19']);
  });

  it('o "Mais cedo" de exemplo é a primeira abertura que ainda não passou, no fuso da página', () => {
    // 12:00 em São Paulo (UTC-3).
    const noon = new Date('2026-10-12T15:00:00Z');
    const days = ['2026-10-12', '2026-10-14'];
    expect(previewEarliest(days, 8, 'America/Sao_Paulo', noon)).toBe(
      '2026-10-14T11:00:00.000Z'
    );
    // Em Manaus (UTC-4) as mesmas 8 horas são uma hora depois.
    expect(previewEarliest(days, 8, 'America/Manaus', noon)).toBe(
      '2026-10-14T12:00:00.000Z'
    );
    // Abertura de hoje que ainda não passou vale.
    expect(previewEarliest(days, 13, 'America/Sao_Paulo', noon)).toBe(
      '2026-10-12T16:00:00.000Z'
    );
    expect(previewEarliest([], 8, 'America/Sao_Paulo', noon)).toBeNull();
    // Dia de troca de horário em Nova York: 03:00 de 01/11 já é horário de inverno (UTC-5) e 03:00 de 08/03 já
    // é de verão (UTC-4).
    const before = new Date('2026-01-01T00:00:00Z');
    expect(previewEarliest(['2026-11-01'], 3, 'America/New_York', before)).toBe(
      '2026-11-01T08:00:00.000Z'
    );
    expect(previewEarliest(['2026-03-08'], 3, 'America/New_York', before)).toBe(
      '2026-03-08T07:00:00.000Z'
    );
  });

  it('usa o fuso da página; sem fuso válido, o de quem vê', () => {
    expect(previewZone({ preview: { timezone: 'America/Manaus' } })).toBe(
      'America/Manaus'
    );
    const local = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
    expect(previewZone({ preview: { timezone: 'Brasilia' } })).toBe(local);
    expect(previewZone({})).toBe(local);
  });

  it('o dia vira no fuso da página, não no de quem vê', () => {
    // 01:00 UTC de 13/10 ainda é 12/10 em São Paulo e já é 13/10 em Tóquio.
    const now = new Date('2026-10-13T01:00:00Z');
    const all = {
      ...page,
      working_hours: { ...page.working_hours, weekdays: [0, 1, 2, 3, 4, 5, 6] },
    };
    const inZone = timezone =>
      previewDays(pageToForm(all), { ...all, preview: { timezone } }, now)[0];
    expect(inZone('America/Sao_Paulo')).toBe('2026-10-12');
    expect(inZone('Asia/Tokyo')).toBe('2026-10-13');
  });

  it('feriado fechado some dos dias; com "fechar nos feriados" desligado, volta', () => {
    const now = new Date('2026-10-12T12:00:00Z');
    const closed = {
      ...page,
      preview: { timezone: 'America/Sao_Paulo', closed_dates: ['2026-10-12'] },
    };
    expect(previewDays(pageToForm(closed), closed, now)).toEqual([
      '2026-10-14',
      '2026-10-19',
    ]);
    const open = { ...closed, close_holidays: false };
    expect(previewDays(pageToForm(open), open, now)[0]).toBe('2026-10-12');
  });

  it('foto: a da página, depois a que a pessoa guardou, depois a do perfil', () => {
    const saved = {
      ...page,
      people: [
        {
          ...page.people[0],
          booking_photo_url: 'https://cdn.exemplo.com/guardada.png',
        },
      ],
    };
    expect(publicPageFrom(pageToForm(saved), saved).agent_photo_url).toBe(
      'https://cdn.exemplo.com/guardada.png'
    );
    expect(publicPageFrom(pageToForm(page), page).agent_photo_url).toBe(
      'https://cdn.exemplo.com/maria.png'
    );
    const withPagePhoto = {
      ...saved,
      photo_url: 'https://cdn.exemplo.com/pagina.png',
    };
    expect(
      publicPageFrom(pageToForm(withPagePhoto), withPagePhoto).brand.photo_url
    ).toBe('https://cdn.exemplo.com/pagina.png');
  });
});

describe('cor pronta ou própria e identidade no formulário', () => {
  it('reconhece cor pronta sem ligar para maiúsculas; outra cor é própria', () => {
    expect(presetColor('#0b7a5a').key).toBe('GREEN');
    expect(presetColor('#0B7A5A').key).toBe('GREEN');
    expect(presetColor('#ffe066')).toBeNull();
    expect(presetColor(undefined)).toBeNull();
  });

  it('lado da logo: esquerda por padrão, e volta o que a página tem', () => {
    expect(pageToForm({ ...page, brand: {} }).logoAlign).toBe('left');
    expect(pageToForm(page).logoAlign).toBe('center');
  });

  it('identidade aplicada vira cor, frase e lado no formulário', () => {
    expect(brandFormPatch(page)).toEqual({
      color: '#ffe066',
      headline: 'Oi',
      logoAlign: 'center',
    });
  });
});
