import multer from 'multer';

const allowedMimeTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/pdf',
]);

export const playerFileUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 4 * 1024 * 1024,
    files: 1,
    fields: 12,
  },
  fileFilter: (_req, file, callback) => {
    if (!allowedMimeTypes.has(file.mimetype)) {
      callback(new Error('Nur PDF-, JPEG-, PNG- und WebP-Dateien sind erlaubt.'));
      return;
    }
    callback(null, true);
  },
});

const familyContactMimeTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'video/mp4',
  'video/webm',
  'audio/mpeg',
  'audio/mp4',
  'audio/aac',
  'audio/ogg',
  'application/pdf',
]);

export const familyContactUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 20 * 1024 * 1024,
    files: 1,
    fields: 12,
  },
  fileFilter: (_req, file, callback) => {
    if (!familyContactMimeTypes.has(file.mimetype)) {
      callback(new Error(
        'Nur Bilder, MP4-/WebM-Videos, Audiodateien und PDF-Dokumente sind erlaubt.',
      ));
      return;
    }
    callback(null, true);
  },
});

