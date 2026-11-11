// #2889 — os tons do quadrado do ícone num catálogo (modelos de automação, vitrine de ferramentas). Classes escritas
// por inteiro para o Tailwind encontrá-las.
export const TONS = {
  azul: 'bg-n-blue-3 text-n-blue-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  ambar: 'bg-n-amber-3 text-n-amber-11',
  rosa: 'bg-n-ruby-3 text-n-ruby-11',
  violeta: 'bg-n-iris-3 text-n-iris-11',
  cinza: 'bg-n-slate-3 text-n-slate-11',
};

export const classeDoTom = tom => TONS[tom] || TONS.azul;
