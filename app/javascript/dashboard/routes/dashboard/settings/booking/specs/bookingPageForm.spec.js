import {
  firstMissingStep,
  formToPayload,
  imageProblem,
  isWebUrl,
  pageToForm,
  stepProblem,
} from '../bookingPageForm';
import { formatMinutes, formatWeekdays } from '../bookingFormat';

// Conversão página ↔ formulário e conferências de cada passo (#1187, F1-D).
const page = {
  title: 'Visita',
  duration_minutes: 60,
  slot_durations: [30],
  people: [{ id: 4, name: 'Maria' }],
  locations: [{ type: 'in_person', address: 'Rua A, 1' }],
  calendar_inbox_id: 9,
  working_hours: { start_hour: 8, end_hour: 12, weekdays: [1, 3] },
  min_notice_minutes: 60,
  buffer_minutes: 5,
  brand: { color: '#B3263E', headline: 'Oi' },
  default_pipeline_id: 2,
  default_stage_id: 20,
};

const t = (key, values) =>
  values === undefined ? key : `${key} ${JSON.stringify(values)}`;

describe('bookingPageForm', () => {
  it('ida e volta mantém o que a página tem', () => {
    const payload = formToPayload(pageToForm(page));
    expect(payload).toEqual({
      title: 'Visita',
      duration_minutes: 60,
      slot_durations: [30],
      locations: [{ type: 'in_person', address: 'Rua A, 1' }],
      calendar_inbox_id: null,
      working_hours: { start_hour: 8, end_hour: 12, weekdays: [1, 3] },
      min_notice_minutes: 60,
      buffer_minutes: 5,
      close_holidays: true,
      brand: { color: '#B3263E', headline: 'Oi' },
      default_pipeline_id: 2,
      default_stage_id: 20,
      notice_preset: 'standard',
      notice_templates: {},
      cancel_until_minutes: 120,
      notice_inbox_id: null,
    });
  });

  it('feriados fechados vêm ligados e só desligam quando a página diz false', () => {
    expect(pageToForm(page).closeHolidays).toBe(true);
    expect(pageToForm({ ...page, close_holidays: true }).closeHolidays).toBe(
      true
    );
    const off = pageToForm({ ...page, close_holidays: false });
    expect(off.closeHolidays).toBe(false);
    expect(formToPayload(off).close_holidays).toBe(false);
  });

  it('avisos: ida e volta com caixa, jogo, modelos e prazo', () => {
    const withNotices = {
      ...page,
      notice_inbox_id: 12,
      notice_preset: 'light',
      notice_templates: {
        booked: { name: 'aviso_marcado', language: 'pt_BR' },
        day_before: { name: 'fora_do_jogo', language: 'pt_BR' },
      },
      cancel_until_minutes: 1440,
    };
    const payload = formToPayload(pageToForm(withNotices));
    expect(payload.notice_inbox_id).toBe(12);
    expect(payload.notice_preset).toBe('light');
    expect(payload.cancel_until_minutes).toBe(1440);
    // "1 dia antes" não está no jogo leve: o modelo dele não vai.
    expect(payload.notice_templates).toEqual({
      booked: { name: 'aviso_marcado', language: 'pt_BR' },
    });
  });

  it('caixa de avisos só vai no PATCH quando muda', () => {
    const saved = { ...page, notice_inbox_id: 12 };
    const form = pageToForm(saved);
    expect('notice_inbox_id' in formToPayload(form, saved)).toBe(false);
    const off = formToPayload({ ...form, noticeInboxId: null }, saved);
    expect(off.notice_inbox_id).toBeNull();
    expect(off.notice_templates).toEqual({});
  });

  it('caixa de agenda só vai junto com Meet ou Teams', () => {
    const form = {
      ...pageToForm(page),
      locations: [{ type: 'teams', url: '', address: '' }],
    };
    expect(formToPayload(form).calendar_inbox_id).toBe(9);
  });

  it('a duração principal não se repete nas extras', () => {
    const form = { ...pageToForm(page), slotDurations: [30, 60] };
    expect(formToPayload(form).slot_durations).toEqual([30]);
  });

  it('confere cada passo', () => {
    const form = pageToForm(page);
    expect(stepProblem(2, { ...form, title: ' ' })).toBe('TITLE');
    expect(stepProblem(2, { ...form, peopleIds: [] })).toBe('PEOPLE');
    expect(stepProblem(3, { ...form, locations: [] })).toBe('LOCATION');
    expect(
      stepProblem(3, {
        ...form,
        locations: [{ type: 'in_person', address: '', url: '' }],
      })
    ).toBe('ADDRESS');
    expect(
      stepProblem(3, {
        ...form,
        calendarInboxId: null,
        locations: [{ type: 'google_meet', address: '', url: '' }],
      })
    ).toBe('CALENDAR');
    expect(stepProblem(4, { ...form, weekdays: [] })).toBe('WEEKDAYS');
    expect(stepProblem(4, { ...form, startHour: 12, endHour: 12 })).toBe(
      'HOURS'
    );
    expect(stepProblem(5, form)).toBeNull();
  });

  it('link só completo, http ou https', () => {
    expect(isWebUrl('https://zoom.us/j/1')).toBe(true);
    expect(isWebUrl('zoom.us/j/1')).toBe(false);
    expect(isWebUrl('ftp://exemplo.com/arquivo')).toBe(false);
  });

  it('imagem: PNG, JPEG ou WebP até 2 MB', () => {
    expect(imageProblem({ type: 'image/svg+xml', size: 1 })).toBe('IMAGE_TYPE');
    expect(imageProblem({ type: 'image/png', size: 3 * 1024 * 1024 })).toBe(
      'IMAGE_SIZE'
    );
    expect(imageProblem({ type: 'image/webp', size: 1024 })).toBeNull();
  });

  it('a primeira pendência leva ao passo que a resolve', () => {
    expect(firstMissingStep(['working_hours', 'host'])).toBe(2);
    expect(firstMissingStep(['location'])).toBe(3);
  });

  it('formata duração e dias em texto', () => {
    expect(formatMinutes(t, 45)).toBe('BOOKING.FORMAT.MINUTES {"n":45}');
    expect(formatMinutes(t, 60)).toBe('BOOKING.FORMAT.ONE_HOUR');
    expect(formatMinutes(t, 90)).toBe(
      'BOOKING.FORMAT.MIXED {"hours":1,"minutes":30}'
    );
    expect(formatMinutes(t, 2880)).toBe('BOOKING.FORMAT.DAYS {"n":2}');
    expect(formatWeekdays(t, [1, 2, 3, 4, 5])).toContain(
      'BOOKING.FORMAT.DAY_RANGE'
    );
    expect(formatWeekdays(t, [5, 1])).toBe(
      'BOOKING.WEEKDAYS.MON, BOOKING.WEEKDAYS.FRI'
    );
  });
});
