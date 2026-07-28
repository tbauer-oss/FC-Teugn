import { Request, Response, NextFunction } from 'express';
import multer from 'multer';

export function errorHandler(err: any, _req: Request, res: Response, _next: NextFunction) {
  console.error(err);
  if (res.headersSent) {
    return;
  }
  if (err instanceof multer.MulterError) {
    const status = err.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
    const message =
      err.code === 'LIMIT_FILE_SIZE'
        ? 'Die Datei ist zu groß. Maximal sind 4 MB erlaubt.'
        : 'Die Datei konnte nicht verarbeitet werden.';
    res.status(status).json({ message });
    return;
  }
  if (err instanceof Error && err.message.includes('PDF-, JPEG-')) {
    res.status(415).json({ message: err.message });
    return;
  }
  res.status(500).json({ message: 'Internal server error' });
}
