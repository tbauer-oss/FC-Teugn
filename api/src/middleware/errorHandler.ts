import { Request, Response, NextFunction } from 'express';
import multer from 'multer';
import { BlobError } from '@vercel/blob';
import { Prisma } from '@prisma/client';

export function errorHandler(err: any, req: Request, res: Response, _next: NextFunction) {
  const requestId = String(res.locals.requestId || 'unknown');
  const safeLog = {
    requestId,
    method: req.method,
    path: req.path,
    errorName: err instanceof Error ? err.name : 'UnknownError',
    errorCode:
      err instanceof Prisma.PrismaClientKnownRequestError
        ? err.code
        : typeof err?.code === 'string'
          ? err.code
          : undefined,
    message:
      process.env.NODE_ENV === 'production'
        ? 'Request failed'
        : err instanceof Error
          ? err.message
          : 'Unknown error',
  };
  console.error('[api-error]', safeLog);
  if (res.headersSent) {
    return;
  }
  if (err instanceof multer.MulterError) {
    const status = err.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
    const message =
      err.code === 'LIMIT_FILE_SIZE'
        ? 'Die Datei ist zu groß. Maximal sind 4 MB erlaubt.'
        : 'Die Datei konnte nicht verarbeitet werden.';
    res.status(status).json({ message, requestId });
    return;
  }
  if (err instanceof Error && err.message.includes('PDF-, JPEG-')) {
    res.status(415).json({ message: err.message, requestId });
    return;
  }
  const isMissingBlobCredentials =
    err instanceof Error &&
    err.message.includes('Vercel Blob: No blob credentials found');
  if (err instanceof BlobError || isMissingBlobCredentials) {
    res.status(503).json({
      message:
        'Der geschützte Fotospeicher ist momentan nicht erreichbar. Die Blob-Verbindung des Backend-Projekts ist nicht vollständig konfiguriert.',
      requestId,
    });
    return;
  }
  if (
    err instanceof Prisma.PrismaClientKnownRequestError &&
    ['P2024', 'P2028'].includes(err.code)
  ) {
    res.status(503).json({
      message:
        'Die Vereinsdatenbank war kurzzeitig ausgelastet. Die Änderung konnte noch nicht bestätigt und kann sicher erneut gesendet werden.',
      code: err.code,
      requestId,
    });
    return;
  }
  if (err instanceof Prisma.PrismaClientInitializationError) {
    res.status(503).json({
      message:
        'Die Vereinsdatenbank wird gerade neu verbunden. Bitte die Änderung erneut senden.',
      code: 'DATABASE_CONNECTION',
      requestId,
    });
    return;
  }
  res.status(500).json({
    message: 'Die Vereinsverwaltung konnte die Anfrage nicht abschließen.',
    code: 'INTERNAL_ERROR',
    requestId,
  });
}
