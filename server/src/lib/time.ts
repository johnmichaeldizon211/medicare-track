export function addDurationToNow(duration: string): Date {
  const match = duration.match(/^(\d+)([smhd])$/i);
  if (!match) {
    const fallback = new Date();
    fallback.setDate(fallback.getDate() + 7);
    return fallback;
  }

  const amount = Number(match[1]);
  const unit = match[2].toLowerCase();
  const now = new Date();

  if (unit === "s") now.setSeconds(now.getSeconds() + amount);
  if (unit === "m") now.setMinutes(now.getMinutes() + amount);
  if (unit === "h") now.setHours(now.getHours() + amount);
  if (unit === "d") now.setDate(now.getDate() + amount);

  return now;
}
