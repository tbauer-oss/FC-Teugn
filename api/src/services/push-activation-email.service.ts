import { externalDeliveriesAllowed } from '../lib/runtime-environment';

const resendEndpoint = 'https://api.resend.com/emails';
const resendTimeoutMs = 8_000;

type PushActivationEmailInput = {
  recipient: string;
  recipientName: string;
  reminderId: string;
  settingsPath: string;
};

function escapeHtml(value: string) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function publicAppUrl() {
  return (
    process.env.PUBLIC_APP_URL?.trim() || 'https://fcteugnapp.vercel.app'
  ).replace(/\/$/, '');
}

export async function sendPushActivationEmail(
  input: PushActivationEmailInput,
) {
  if (!externalDeliveriesAllowed) return false;
  const apiKey = process.env.RESEND_API_KEY?.trim();
  const from = process.env.RESEND_SUPPORT_FROM_EMAIL?.trim() ||
    'FC Teugn Talents Support <support@fc-teugn-talents.de>';
  if (!apiKey) {
    console.warn(
      '[push-activation-email] RESEND_API_KEY is not configured',
    );
    return false;
  }

  const settingsUrl = `${publicAppUrl()}/#${input.settingsPath}`;
  const safeName = escapeHtml(input.recipientName);
  const safeUrl = escapeHtml(settingsUrl);
  const replyTo = process.env.RESEND_SUPPORT_REPLY_TO?.trim() ||
    process.env.RESEND_REPLY_TO?.trim();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), resendTimeoutMs);

  try {
    const response = await fetch(resendEndpoint, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'User-Agent': 'FC-Teugn-Talents/1.0',
        'Idempotency-Key': `push-activation-reminder-${input.reminderId}`,
      },
      body: JSON.stringify({
        from,
        to: [input.recipient],
        subject: 'FC Teugn Talents: Pushnachrichten aktivieren',
        text: [
          `Hallo ${input.recipientName},`,
          '',
          'für deinen Zugang zu FC Teugn Talents ist derzeit kein Gerät für Pushnachrichten registriert. So verpasst du keine kurzfristigen Änderungen, Erinnerungen oder Spielinformationen:',
          '',
          'Android:',
          '1. App öffnen und anmelden.',
          '2. Mehr > Mitteilungscenter > Einstellungen öffnen.',
          '3. Pushnachrichten und die gewünschten Kategorien aktivieren.',
          '4. Die Android-Abfrage erlauben. Falls sie blockiert ist: Einstellungen > Apps > FC Teugn Talents > Benachrichtigungen.',
          '',
          'iPhone:',
          '1. Die App über Safari mit Teilen > Zum Home-Bildschirm installieren und anschließend über das App-Symbol öffnen.',
          '2. Mehr > Mitteilungscenter > Einstellungen öffnen.',
          '3. Pushnachrichten aktivieren und die iOS-Abfrage erlauben. Falls sie blockiert ist: Einstellungen > Mitteilungen > FC Teugn Talents.',
          '',
          'Web:',
          '1. App im Browser öffnen und anmelden.',
          '2. Mehr > Mitteilungscenter > Einstellungen öffnen.',
          '3. Pushnachrichten aktivieren und die Browser-Abfrage erlauben. Falls nötig, Benachrichtigungen in den Website-Einstellungen des Browsers zulassen.',
          '',
          `Direkt zu den Einstellungen: ${settingsUrl}`,
          '',
          'Hinweis: Pushnachrichten werden pro Gerät aktiviert. Diese E-Mail enthält keine Zugangsdaten.',
        ].join('\n'),
        html: `<!doctype html>
<html lang="de">
  <body style="margin:0;background:#f5f5f0;color:#171813;font-family:Arial,sans-serif">
    <div style="display:none;max-height:0;overflow:hidden">Pushnachrichten für FC Teugn Talents in wenigen Schritten aktivieren.</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f5f0;padding:24px 12px">
      <tr><td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#ffffff;border:1px solid #dddccf;border-radius:20px;overflow:hidden">
          <tr><td style="background:#111511;padding:24px 28px;color:#ffe000;font-size:22px;font-weight:700">FC TEUGN TALENTS</td></tr>
          <tr><td style="padding:30px 28px">
            <h1 style="margin:0 0 18px;font-size:26px;line-height:1.2">Pushnachrichten aktivieren</h1>
            <p style="margin:0 0 16px;line-height:1.55">Hallo ${safeName},</p>
            <p style="margin:0 0 24px;line-height:1.55">für deinen Zugang ist derzeit kein Gerät für Pushnachrichten registriert. Aktiviere sie, damit du kurzfristige Änderungen, Erinnerungen und Spielinformationen zuverlässig erhältst.</p>
            <p style="margin:0 0 26px"><a href="${safeUrl}" style="display:inline-block;background:#ffe000;color:#171813;text-decoration:none;font-weight:700;padding:14px 20px;border-radius:12px">Push-Einstellungen öffnen</a></p>
            <h2 style="margin:22px 0 8px;font-size:18px">Android</h2>
            <ol style="margin:0 0 18px;padding-left:22px;line-height:1.6"><li>App öffnen und anmelden.</li><li><strong>Mehr → Mitteilungscenter → Einstellungen</strong> öffnen.</li><li>Pushnachrichten und Kategorien aktivieren und die Android-Abfrage erlauben.</li></ol>
            <p style="margin:0 0 18px;color:#66665e;font-size:14px;line-height:1.5">Falls blockiert: Einstellungen → Apps → FC Teugn Talents → Benachrichtigungen.</p>
            <h2 style="margin:22px 0 8px;font-size:18px">iPhone</h2>
            <ol style="margin:0 0 18px;padding-left:22px;line-height:1.6"><li>In Safari über <strong>Teilen → Zum Home-Bildschirm</strong> installieren und über das App-Symbol öffnen.</li><li><strong>Mehr → Mitteilungscenter → Einstellungen</strong> öffnen.</li><li>Pushnachrichten aktivieren und die iOS-Abfrage erlauben.</li></ol>
            <p style="margin:0 0 18px;color:#66665e;font-size:14px;line-height:1.5">Falls blockiert: Einstellungen → Mitteilungen → FC Teugn Talents.</p>
            <h2 style="margin:22px 0 8px;font-size:18px">Web</h2>
            <ol style="margin:0 0 18px;padding-left:22px;line-height:1.6"><li>App im Browser öffnen und anmelden.</li><li><strong>Mehr → Mitteilungscenter → Einstellungen</strong> öffnen.</li><li>Pushnachrichten aktivieren und die Browser-Abfrage erlauben.</li></ol>
            <p style="margin:24px 0 0;color:#66665e;font-size:14px;line-height:1.5">Pushnachrichten werden pro Gerät aktiviert. Diese E-Mail enthält keine Zugangsdaten.</p>
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`,
        ...(replyTo ? { reply_to: replyTo } : {}),
        tags: [
          { name: 'purpose', value: 'push-activation' },
          { name: 'reminder_id', value: input.reminderId },
        ],
      }),
    });

    if (!response.ok) {
      const providerMessage = await response.text();
      console.error(
        `[push-activation-email] Resend rejected request with status ${response.status}: ${providerMessage}`,
      );
      return false;
    }
    const result = (await response.json()) as { id?: unknown };
    return typeof result.id === 'string' && result.id.length > 0;
  } catch (error) {
    console.error(
      '[push-activation-email] Resend request failed',
      error instanceof Error ? error.name : 'UnknownError',
    );
    return false;
  } finally {
    clearTimeout(timeout);
  }
}
