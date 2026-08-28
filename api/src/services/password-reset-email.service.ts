const resendEndpoint = 'https://api.resend.com/emails';
const resendTimeoutMs = 8_000;

type PasswordResetEmailInput = {
  recipient: string;
  recipientName: string;
  token: string;
  resetId: string;
  expiresAt: Date;
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

export async function sendPasswordResetEmail(
  input: PasswordResetEmailInput,
) {
  const apiKey = process.env.RESEND_API_KEY?.trim();
  const from = process.env.RESEND_ACCOUNT_FROM_EMAIL?.trim() ||
    'FC Teugn Talents <account@fc-teugn-talents.de>';
  if (!apiKey) {
    console.warn(
      '[password-reset-email] RESEND_API_KEY is not configured',
    );
    return false;
  }

  // Use a regular HTTPS path instead of a hash-only route. Mail clients,
  // security scanners and optional click tracking may discard URL fragments
  // before the browser reaches the app. Vercel rewrites this path to the
  // Flutter entry page, which converts it to the internal hash route locally.
  const resetUrl = `${publicAppUrl()}/reset-password?token=${encodeURIComponent(
    input.token,
  )}`;
  const safeName = escapeHtml(input.recipientName);
  const safeUrl = escapeHtml(resetUrl);
  const replyTo = process.env.RESEND_ACCOUNT_REPLY_TO?.trim() ||
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
        'Idempotency-Key': `password-reset-${input.resetId}`,
      },
      body: JSON.stringify({
        from,
        to: [input.recipient],
        subject: 'FC Teugn Talents: Passwort zurücksetzen',
        text: [
          `Hallo ${input.recipientName},`,
          '',
          'über diesen sicheren Link kannst du innerhalb von 15 Minuten ein neues Passwort für FC Teugn Talents festlegen:',
          resetUrl,
          '',
          'Der Link ist nur einmal verwendbar. Falls du die Änderung nicht angefordert hast, kannst du diese E-Mail ignorieren.',
        ].join('\n'),
        html: `<!doctype html>
<html lang="de">
  <body style="margin:0;background:#f5f5f0;color:#171813;font-family:Arial,sans-serif">
    <div style="display:none;max-height:0;overflow:hidden">Sicherer Einmallink zum Zurücksetzen deines Passworts.</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f5f0;padding:24px 12px">
      <tr><td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border:1px solid #dddccf;border-radius:20px;overflow:hidden">
          <tr><td style="background:#111511;padding:24px 28px;color:#ffe000;font-size:22px;font-weight:700">FC TEUGN TALENTS</td></tr>
          <tr><td style="padding:30px 28px">
            <h1 style="margin:0 0 18px;font-size:26px;line-height:1.2">Passwort zurücksetzen</h1>
            <p style="margin:0 0 16px;line-height:1.55">Hallo ${safeName},</p>
            <p style="margin:0 0 24px;line-height:1.55">über den folgenden sicheren Link kannst du innerhalb von <strong>15 Minuten</strong> ein neues Passwort festlegen.</p>
            <p style="margin:0 0 24px"><a href="${safeUrl}" style="display:inline-block;background:#ffe000;color:#171813;text-decoration:none;font-weight:700;padding:14px 20px;border-radius:12px">Neues Passwort festlegen</a></p>
            <p style="margin:0;color:#66665e;font-size:14px;line-height:1.5">Der Link ist nur einmal verwendbar. Falls du diese Änderung nicht angefordert hast, kannst du die E-Mail ignorieren.</p>
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`,
        ...(replyTo ? { reply_to: replyTo } : {}),
        tags: [
          { name: 'purpose', value: 'password-reset' },
          { name: 'reset_id', value: input.resetId },
        ],
      }),
    });

    if (!response.ok) {
      const providerMessage = await response.text();
      console.error(
        `[password-reset-email] Resend rejected request with status ${response.status}: ${providerMessage}`,
      );
      return false;
    }
    const result = (await response.json()) as { id?: unknown };
    return typeof result.id === 'string' && result.id.length > 0;
  } catch (error) {
    console.error(
      '[password-reset-email] Resend request failed',
      error instanceof Error ? error.name : 'UnknownError',
    );
    return false;
  } finally {
    clearTimeout(timeout);
  }
}
