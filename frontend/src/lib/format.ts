export function brl(value: number): string {
  return value.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

export function formatDate(input: any): string {
  if (!input) return '';
  const d = input?._seconds
    ? new Date(input._seconds * 1000)
    : input?.seconds
      ? new Date(input.seconds * 1000)
      : new Date(input);
  if (isNaN(d.getTime())) return '';
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' });
}
