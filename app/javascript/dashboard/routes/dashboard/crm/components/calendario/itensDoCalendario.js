// Calendário Ouro — de evento do back para "item": o tipo em palavra simples,
// o dia (no fuso da conta), se atrasou, se dá para marcar como feito e qual é
// a única ação que o item oferece.
import { chaveDoDia, minutosDoDia } from './tempoNaConta';

// Cor só para o tipo no ícone; vermelho fica reservado para "atrasado".
export const TIPOS = {
  lembrete: {
    icone: 'i-lucide-bell',
    tom: 'bg-n-teal-3 text-n-teal-11',
    ponto: 'bg-n-teal-9',
    borda: 'border-s-n-teal-9',
  },
  mensagem: {
    icone: 'i-lucide-send',
    tom: 'bg-n-blue-3 text-n-blue-11',
    ponto: 'bg-n-blue-9',
    borda: 'border-s-n-blue-9',
  },
  reuniao: {
    icone: 'i-lucide-video',
    tom: 'bg-n-iris-3 text-n-iris-11',
    ponto: 'bg-n-iris-9',
    borda: 'border-s-n-iris-9',
  },
  fechar: {
    icone: 'i-lucide-flag',
    tom: 'bg-n-amber-3 text-n-amber-11',
    ponto: 'bg-n-amber-9',
    borda: 'border-s-n-amber-9',
  },
  agenda: {
    icone: 'i-lucide-calendar',
    tom: 'bg-n-alpha-2 text-n-slate-11',
    ponto: 'bg-n-slate-8',
    borda: 'border-s-n-slate-8',
  },
};

export const ORDEM_DOS_TIPOS = [
  'lembrete',
  'reuniao',
  'mensagem',
  'fechar',
  'agenda',
];

const FEITOS = ['done', 'completed', 'sent', 'cancelled', 'canceled'];

export const tipoDoEvento = evento => {
  switch (evento.event_type) {
    case 'meeting':
      return 'reuniao';
    case 'external':
      return 'agenda';
    case 'expected_close':
      return 'fechar';
    case 'follow_up_auto_send_message':
      return 'mensagem';
    default:
      return 'lembrete';
  }
};

// O contato e o número da conversa vêm no próprio evento (#1568). Dia inteiro
// (vencimento do card, compromisso de dia todo da agenda) não tem hora: o dia é
// o `date` que o back manda, a parte UTC da data (#1541).
const contatoDoEvento = evento =>
  evento.contact_name || evento.contact_phone
    ? { nome: evento.contact_name || '', telefone: evento.contact_phone || '' }
    : null;

export const paraItem = (evento, { fuso, agora }) => {
  const tipo = tipoDoEvento(evento);
  const inicio = new Date(evento.starts_at);
  const diaTodo = evento.all_day === true;
  const feito = FEITOS.includes(String(evento.status || '').toLowerCase());
  const virtual = evento.virtual === true;
  return {
    id: evento.id,
    evento,
    tipo,
    titulo: evento.title || '',
    contato: contatoDoEvento(evento),
    diaTodo,
    chave: diaTodo && evento.date ? evento.date : chaveDoDia(inicio, fuso),
    minutos: diaTodo ? -1 : minutosDoDia(inicio, fuso),
    inicio,
    fim: evento.ends_at ? new Date(evento.ends_at) : null,
    feito,
    virtual,
    repete: evento.recurring === true,
    pausado: evento.status === 'paused',
    atrasado: tipo === 'lembrete' && !feito && !virtual && inicio < agora,
    podeConcluir: tipo === 'lembrete' && !feito && !virtual,
    // #1855: envio ao cliente (mensagem marcada, ou o aviso de uma que não
    // saiu). Fica fora do "Passar os meus para amanhã".
    envio: tipo === 'mensagem' || evento.automatic_send === true,
    // #1590: por que a mensagem marcada não saiu (código; a frase é da tela).
    falha: evento.send_error_code || '',
  };
};

export const porHorario = (a, b) =>
  a.chave.localeCompare(b.chave) || a.minutos - b.minutos;

// A única ação do item. Abrir conversa vem antes de ligar: a conversa é o
// canal que a conta tem conectado; o telefone só aparece sem conversa.
export const acaoDoItem = (item, { hoje }) => {
  const { evento, tipo } = item;
  if (tipo === 'agenda') return null;
  if (tipo === 'reuniao') {
    return evento.online_meeting_url && item.chave === hoje
      ? {
          chave: 'ENTRAR',
          icone: 'i-lucide-video',
          link: evento.online_meeting_url,
        }
      : { chave: 'VER_REUNIAO', icone: 'i-lucide-calendar-check', abrir: true };
  }
  if (tipo === 'fechar') {
    return { chave: 'VER_NEGOCIO', icone: 'i-lucide-briefcase', abrir: true };
  }
  if (tipo === 'mensagem') {
    return { chave: 'VER_MENSAGEM', icone: 'i-lucide-send', abrir: true };
  }
  if (evento.conversation_display_id) {
    return {
      chave: 'ABRIR_CONVERSA',
      icone: 'i-lucide-message-circle',
      conversa: evento.conversation_display_id,
    };
  }
  if (item.contato?.telefone) {
    return {
      chave: 'LIGAR',
      icone: 'i-lucide-phone',
      link: `tel:${item.contato.telefone}`,
    };
  }
  return { chave: 'VER', icone: 'i-lucide-eye', abrir: true };
};

// Na lista dos próximos dias, um lembrete que repete aparece uma vez só.
export const semRepeticoes = itens => {
  const vistos = new Set();
  return itens.filter(item => {
    const serie = item.evento.series_id;
    if (!serie) return true;
    if (vistos.has(serie)) return false;
    vistos.add(serie);
    return true;
  });
};
